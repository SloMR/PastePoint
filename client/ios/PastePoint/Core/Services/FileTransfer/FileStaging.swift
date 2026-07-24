//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation
import PhotosUI
import SwiftUI

/// Receives a picked photo/video as a file (not bytes), so we never load the
/// whole asset into RAM. The system's temp file is deleted after the importing
/// closure, so we copy it (file→file) into our tmp.
private struct StagedPhotoFile: Transferable {
  let url: URL

  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(importedContentType: .data) { received in
      let dest = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(UUID().uuidString)-\(received.file.lastPathComponent)")
      try FileManager.default.copyItem(at: received.file, to: dest)
      return Self(url: dest)
    }
  }
}

/// Copies picked files/photos into the app tmp dir and returns `StagedFile`s.
/// Shared by the broadcast input bar and the per-member send button.
enum FileStaging {

  private static let photoNameFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
  }()

  /// Files-app picks: hold security-scoped access and read the original lazily —
  /// no copy into the app sandbox. Access is released in `releaseSource(at:)`
  /// (chip removed, or last upload finished).
  static func stage(urls: [URL]) async -> [StagedFile] {
    var staged: [StagedFile] = []
    for url in urls {
      guard url.startAccessingSecurityScopedResource() else {
        log.error("couldn't access security-scoped \(url.lastPathComponent)")
        continue
      }

      let fileName = url.lastPathComponent
      do {
        let size = Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        staged.append(StagedFile(id: UUID(), name: fileName, size: size, url: url, kind: .securityScoped))
        log.info("staged file: \(fileName) (\(size) bytes)")
      } catch {
        url.stopAccessingSecurityScopedResource()
        log.error("failed to stat \(fileName): \(String(describing: error))")
      }
    }
    return staged
  }

  /// Photos picks: load bytes, write to tmp.
  static func stage(photoItems: [PhotosPickerItem]) async -> [StagedFile] {
    var staged: [StagedFile] = []
    for item in photoItems {
      do {
        guard let picked = try await item.loadTransferable(type: StagedPhotoFile.self) else {
          log.error("photosPicker item returned nil file")
          continue
        }

        let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "bin"
        let displayName = "Photo-\(Self.photoNameFormatter.string(from: Date()))-\(UUID().uuidString.prefix(4)).\(ext)"
        let size = Int64((try? picked.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)

        staged.append(StagedFile(id: UUID(), name: displayName, size: size, url: picked.url, kind: .ownedTemp))
        log.info("staged photo: \(displayName) (\(size) bytes)")
      } catch {
        log.error("failed to stage photo: \(String(describing: error))")
      }
    }

    return staged
  }

  /// Camera capture: photo bytes → write to tmp; video temp file → copy to tmp.
  /// Both are owned temp files.
  static func stage(camera capture: CameraCapture) async -> [StagedFile] {
    let stamp = Self.photoNameFormatter.string(from: Date())
    let suffix = UUID().uuidString.prefix(4)

    do {
      switch capture {
      case .photo(let data):
        let name = "Photo-\(stamp)-\(suffix).jpg"
        let size = Int64(data.count)
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(name)

        try data.write(to: dest)
        return [StagedFile(id: UUID(), name: name, size: size, url: dest, kind: .ownedTemp)]
      case .video(let src):
        let ext = src.pathExtension.isEmpty ? "mov" : src.pathExtension
        let name = "Video-\(stamp)-\(suffix).\(ext)"
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(name)

        try FileManager.default.copyItem(at: src, to: dest)

        let size = Int64((try? dest.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        return [StagedFile(id: UUID(), name: name, size: size, url: dest, kind: .ownedTemp)]
      }
    } catch {
      log.error("failed to stage camera capture: \(String(describing: error))")
      return []
    }
  }
}
