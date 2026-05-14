//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import CoreImage.CIFilterBuiltins
import Logging
import SwiftUI

struct QRCodeView: View {
  let text: String
  let size: CGFloat

  private let context = CIContext()

  var body: some View {
    if let image = generateQRCode(from: text) {
      Image(uiImage: image)
        .interpolation(.none)
        .resizable()
        .scaledToFit()
        .frame(width: size, height: size)
    }
  }

  private func generateQRCode(from text: String) -> UIImage? {
    let filter = CIFilter.qrCodeGenerator()

    filter.message = Data(text.utf8)
    filter.correctionLevel = "L"

    guard
      let outputImage = filter.outputImage,
      let cgImage = context.createCGImage(outputImage, from: outputImage.extent)
    else { return nil }

    return UIImage(cgImage: cgImage)
  }
}

struct SettingsQRCode: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var services: AppServices

  private let logger = Logger(label: "SettingsQRCode")

  @State private var sheetHeight: CGFloat = 420

  var body: some View {
    NavigationStack {
      VStack(spacing: 16) {
        QRCodeView(
          text: "https://\(AppEnvironment.webUrl)/private/\(services.wsService.currentSessionCode ?? "")",
          size: 220,
        )
        .padding(20)
        .background(Color(.white), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
          RoundedRectangle(cornerRadius: 16)
            .stroke(Color(.separator), lineWidth: 1),
        )
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)

        Text("Scan the QR code on another device to join the session")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal)
      }
      .padding()
      .frame(maxWidth: .infinity)
      .fixedSize(horizontal: false, vertical: true)
      .onAppear { logger.info("QR code sheet presented for session: \(services.wsService.currentSessionCode ?? "none")") }
      .onGeometryChange(for: CGFloat.self) { proxy in
          proxy.size.height
      } action: { height in
          guard height > 0 else { return }
          sheetHeight = height + 56
      }
      .navigationTitle("QR Code")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          if #available(iOS 26, *) {
            Button(role: .close) {
              dismiss()
            }
          } else {
            Button { dismiss() } label: {
              ZStack {
                Circle()
                  .fill(Color(UIColor.tertiarySystemFill))
                  .frame(width: 36, height: 36)

                Image(systemName: "xmark")
                  .font(.system(size: 13, weight: .bold, design: .rounded))
                  .foregroundStyle(Color(UIColor.secondaryLabel))
              }
              .contentShape(Circle())
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
    .presentationDetents([.height(sheetHeight)])
    .presentationDragIndicator(.visible)
    .presentationBackground(AppColors.Background.background)
  }
}
