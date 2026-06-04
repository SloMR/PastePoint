//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation
import Logging
import PhotosUI
import SwiftUI

/// Copies picked files/photos into the app tmp dir and returns `StagedFile`s.
/// Shared by the broadcast input bar and the per-member send button.
enum FileStaging {
  private static let logger = Logger(label: "FileStaging")

  private static let photoNameFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
  }()

  /// Files-app picks: security-scoped copy into tmp.
  static func stage(urls: [URL]) async -> [StagedFile] {
    var staged: [StagedFile] = []
    for url in urls {
      let didStart = url.startAccessingSecurityScopedResource()

      defer {
        if didStart {
          url.stopAccessingSecurityScopedResource()
        }
      }

      let fileName = url.lastPathComponent
      let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(fileName)")

      do {
        try FileManager.default.copyItem(at: url, to: tmpURL)
        let attribute = try FileManager.default.attributesOfItem(atPath: tmpURL.path)
        let size = (attribute[.size] as? NSNumber)?.int64Value ?? 0

        staged.append(StagedFile(id: UUID(), name: fileName, size: size, url: tmpURL))
        logger.info("staged file: \(fileName) (\(size) bytes)")
      } catch {
        logger.error("failed to stage \(fileName): \(String(describing: error))")
      }
    }

    return staged
  }

  /// Photos picks: load bytes, write to tmp.
  static func stage(photoItems: [PhotosPickerItem]) async -> [StagedFile] {
    var staged: [StagedFile] = []

    for item in photoItems {
      do {
        guard let data = try await item.loadTransferable(type: Data.self) else {
          logger.error("photosPicker item returned nil data")
          continue
        }

        let fileExtension = item.supportedContentTypes.first?.preferredFilenameExtension ?? "bin"
        let displayName = "Photo-\(Self.photoNameFormatter.string(from: Date()))-\(UUID().uuidString.prefix(4)).\(fileExtension)"
        let tmpURL = FileManager.default.temporaryDirectory
          .appendingPathComponent("\(UUID().uuidString)-\(displayName)")

        try data.write(to: tmpURL)
        staged.append(StagedFile(id: UUID(), name: displayName, size: Int64(data.count), url: tmpURL))
        logger.info("staged photo: \(displayName) (\(data.count) bytes)")
      } catch {
        logger.error("failed to stage photo: \(String(describing: error))")
      }
    }

    return staged
  }
}
