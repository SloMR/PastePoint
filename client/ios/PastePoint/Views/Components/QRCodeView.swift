//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import CoreImage.CIFilterBuiltins
import SwiftUI

struct QRCodeView: View {
  let text: String
  let size: CGFloat

  @State private var qrImage: UIImage?

  var body: some View {
    Group {
      if let qrImage {
        Image(uiImage: qrImage)
          .interpolation(.none)
          .resizable()
          .scaledToFit()
          .frame(width: size, height: size)
      } else {
        Color.clear.frame(width: size, height: size)
      }
    }
    .task(id: text) { qrImage = Self.generateQRCode(from: text) }
  }

  private static func generateQRCode(from text: String) -> UIImage? {
    let filter = CIFilter.qrCodeGenerator()

    filter.message = Data(text.utf8)
    filter.correctionLevel = "L"

    guard
      let outputImage = filter.outputImage,
      let cgImage = CIContext().createCGImage(outputImage, from: outputImage.extent)
    else { return nil }

    return UIImage(cgImage: cgImage)
  }
}
