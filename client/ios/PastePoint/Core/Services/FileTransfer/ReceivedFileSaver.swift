//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation
import Photos
import UniformTypeIdentifiers

/// Routes a finished download to its final home: images/videos into the Photos
/// library, everything else into the app's Documents folder. The tmp buffer is
/// consumed (moved) or deleted afterwards — nothing lingers.
enum ReceivedFileSaver {

  enum Outcome: Sendable {
    case photos
    case documents(URL)
    case permissionDenied
    case failed
  }

  nonisolated static func save(at url: URL, fileName: String) async -> Outcome {
    let type = UTType(filenameExtension: url.pathExtension)
    if let type, type.conforms(to: .image) || type.conforms(to: .audiovisualContent) {
      return await saveToPhotos(url: url, isVideo: type.conforms(to: .audiovisualContent))
    }
    return saveToDocuments(url: url, fileName: fileName)
  }

  // MARK: Photos

  private nonisolated static func saveToPhotos(url: URL, isVideo: Bool) async -> Outcome {
    let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    guard status == .authorized || status == .limited else {
      log.error("Photos add permission denied")
      return .permissionDenied
    }

    return await withCheckedContinuation { continuation in
      PHPhotoLibrary.shared().performChanges {
        let request = PHAssetCreationRequest.forAsset()
        request.creationDate = Date()
        request.addResource(with: isVideo ? .video : .photo, fileURL: url, options: nil)
      } completionHandler: { success, error in
        if success {
          try? FileManager.default.removeItem(at: url)
          log.info("saved to Photos: \(url.lastPathComponent)")
          continuation.resume(returning: .photos)
        } else {
          log.error("Photos save failed: \(String(describing: error))")
          continuation.resume(returning: .failed)
        }
      }
    }
  }

  // MARK: Documents

  private nonisolated static func saveToDocuments(url: URL, fileName: String) -> Outcome {
    do {
      let docs = try FileManager.default.url(
        for: .documentDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true,
      )

      let dest = uniqueURL(in: docs, fileName: fileName)
      try FileManager.default.moveItem(at: url, to: dest)
      log.info("saved to Documents: \(dest.lastPathComponent)")
      return .documents(dest)
    } catch {
      log.error("Documents save failed: \(String(describing: error))")
      return .failed
    }
  }

  private nonisolated static func uniqueURL(in dir: URL, fileName: String) -> URL {
    let base = (fileName as NSString).deletingPathExtension
    let ext = (fileName as NSString).pathExtension
    var candidate = dir.appendingPathComponent(fileName)
    var number = 1
    while FileManager.default.fileExists(atPath: candidate.path) {
      let name = ext.isEmpty ? "\(base)-\(number)" : "\(base)-\(number).\(ext)"
      candidate = dir.appendingPathComponent(name)
      number += 1
    }
    return candidate
  }
}
