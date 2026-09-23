//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import CryptoKit
import Foundation
import ImageIO

enum FileTransferValidation {
  static let maxPendingOffersPerPeer = 100
  private nonisolated static let maxPreviewDataUrlBytes = 150 * 1024
  private nonisolated static let maxPreviewPixelSize = 1024
  private nonisolated static let previewDataUrlPrefixes = ["data:image/png;base64,", "data:image/jpeg;base64,"]

  nonisolated static func previewImageData(from dataUrl: String) -> Data? {
    guard
      dataUrl.utf8.count <= maxPreviewDataUrlBytes,
      let prefix = previewDataUrlPrefixes.first(where: { dataUrl.hasPrefix($0) }),
      let data = Data(base64Encoded: String(dataUrl.dropFirst(prefix.count))),
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width <= maxPreviewPixelSize,
      height <= maxPreviewPixelSize
    else {
      return nil
    }
    return data
  }

  /// Scratch directory name for a transfer, derived from the peer's file ID.
  nonisolated static func directoryName(for fileId: String) -> String {
    SHA256.hash(data: Data(fileId.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  /// The peer's file name as a single path component; separators and control characters become `_`.
  nonisolated static func sanitizedFileName(_ fileName: String) -> String {
    let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:*?\"<>|"))
    let underscore: Unicode.Scalar = "_"
    let scalars = fileName.unicodeScalars.map { forbidden.contains($0) ? underscore : $0 }
    let name = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty || name == "." || name == ".." ? "download" : name
  }
}
