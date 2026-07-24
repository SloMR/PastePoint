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

struct SettingsQRCodeView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var services: AppServices

  var body: some View {
    VStack(spacing: 16) {
      QRCodeView(
        text: AppEnvironment.privateSessionUrl(sessionCode: services.wsService.currentSessionCode ?? ""),
        size: 220,
      )
      .padding(20)
      .background(Color(.white), in: RoundedRectangle(cornerRadius: 16))
      .overlay(
        RoundedRectangle(cornerRadius: 16)
          .stroke(Color(.separator), lineWidth: 1),
      )
      .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)

      Text(.scanQrCodeToJoinTheSession)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal)
    }
    .padding()
    .onAppear { log.info("QR code sheet presented for session: \(services.wsService.currentSessionCode ?? "none")") }
    .sheetContainer(title: .qrCode, initialHeight: 420)
  }
}
