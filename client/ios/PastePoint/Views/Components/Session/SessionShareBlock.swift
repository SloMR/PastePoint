//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

/// QR, the code itself, and the two verbs — shared by the connect sheet and the private welcome.
struct SessionShareBlock: View {
  @EnvironmentObject private var toast: ToastCenter

  let code: String
  var qrSize: CGFloat = 180
  var caption: LocalizedStringResource?
  var shareLabel: LocalizedStringResource = .share
  var copyLabel: LocalizedStringResource = .copy

  private var url: String {
    AppEnvironment.privateSessionUrl(sessionCode: code)
  }

  var body: some View {
    VStack(spacing: 12) {
      QRCodeView(text: url, size: qrSize)
        .padding(12)
        .background(Color(.white), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)

      VStack(spacing: 6) {
        if let caption {
          Text(caption)
            .font(.caption2)
            .foregroundStyle(.textSecondary)
        }

        Text(code)
          .font(.system(.body, design: .monospaced).weight(.medium))
          .foregroundStyle(.textPrimary)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 10)
          .background(.inputBackground, in: RoundedRectangle(cornerRadius: 8))
      }

      HStack(spacing: 8) {
        ShareLink(item: url) {
          Text(shareLabel)
        }
        .buttonStyle(.pill(tint: AppColors.Brand.brand))

        Button {
          UIPasteboard.general.string = code
          toast.show(.success(.codeCopied))
        } label: {
          Text(copyLabel)
        }
        .buttonStyle(.pill(.outlined, tint: AppColors.Brand.brand))
      }
    }
  }
}

// MARK: - Preview

#if DEBUG
#Preview {
  PreviewStage {
    SessionShareBlock(code: "K7M2XQ9P4B")
      .padding()
      .environmentObject(ToastCenter())
  }
}
#endif
