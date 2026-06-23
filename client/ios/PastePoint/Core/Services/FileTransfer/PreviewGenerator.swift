//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation
import ImageIO
import Logging
import PDFKit
import UniformTypeIdentifiers

enum PreviewGenerator {
  private nonisolated static let logger = Logger(label: "PreviewGenerator")

  private nonisolated static let maxPixelSize = 320
  private nonisolated static let jpegQuality: CGFloat = 0.7
  private nonisolated static let maxDataUrlBytes = 150 * 1024
  private nonisolated static let maxPdfBytesForPreview = 100 * 1024 * 1024

  struct Preview: Sendable {
    let dataUrl: String
    let mime: String
  }

  nonisolated static func make(forFileAt url: URL) async -> Preview? {
    await Task.detached(priority: .utility) {
      generate(url)
    }.value
  }

  private nonisolated static func generate(_ url: URL) -> Preview? {
    let type = UTType(filenameExtension: url.pathExtension)

    if type?.conforms(to: .image) == true {
      return imagePreview(at: url)
    }
    if type?.conforms(to: .pdf) == true {
      return pdfPreview(at: url)
    }

    return nil
  }

  private nonisolated static func imagePreview(at url: URL) -> Preview? {
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
    ]

    guard
      let src = CGImageSourceCreateWithURL(url as CFURL, nil),
      let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
    else {
      logger.warning("image preview failed")
      return nil
    }

    let image = UIImage(cgImage: cg)

    if let png = image.pngData(), let preview = dataUrl(png, mime: "image/png") {
      return preview
    }

    if
      let jpeg = image.jpegData(compressionQuality: jpegQuality),
      let preview = dataUrl(jpeg, mime: "image/jpeg")
    {
      logger.info("image preview: PNG over cap, used JPEG fallback")
      return preview
    }

    logger.warning("image preview over cap even as JPEG, dropping")
    return nil
  }

  private nonisolated static func pdfPreview(at url: URL) -> Preview? {
    if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int, size > maxPdfBytesForPreview {
      return nil
    }

    guard
      let doc = PDFDocument(url: url),
      let page = doc.page(at: 0)
    else {
      logger.warning("pdf preview failed")
      return nil
    }

    let bounds = page.bounds(for: .mediaBox)
    let ratio = min(CGFloat(maxPixelSize) / bounds.width, 1)
    let target = CGSize(width: bounds.width * ratio, height: bounds.height * ratio)
    guard let data = page.thumbnail(of: target, for: .mediaBox).jpegData(compressionQuality: jpegQuality) else {
      return nil
    }

    guard let preview = dataUrl(data, mime: "image/jpeg") else {
      logger.warning("pdf preview over cap, dropping")
      return nil
    }

    return preview
  }

  private nonisolated static func dataUrl(_ data: Data, mime: String) -> Preview? {
    let dataUrl = "data:\(mime);base64,\(data.base64EncodedString())"
    guard dataUrl.utf8.count <= maxDataUrlBytes else { return nil }
    return Preview(dataUrl: dataUrl, mime: mime)
  }
}
