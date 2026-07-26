//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct WelcomeInviteCard: View {
  let code: String
  let onShowQRCode: () -> Void
  let onCopy: () -> Void

  var body: some View {
    WelcomeCard(title: .inviteTheOtherDevice, message: .inviteShareBody) {
      Text(code)
        .font(.system(.body, design: .monospaced).weight(.medium))
        .foregroundStyle(.textPrimary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.inputBackground, in: RoundedRectangle(cornerRadius: 8))

      HStack(spacing: 8) {
        Button(action: onShowQRCode) {
          HStack(spacing: 6) {
            Image("qrcode")
              .renderingMode(.template)
              .resizable()
              .scaledToFit()
              .frame(width: 16, height: 16)
              .accessibilityHidden(true)
            Text(.showQrCode)
          }
        }
        .buttonStyle(.pill(tint: AppColors.Brand.brand))

        Button(action: onCopy) {
          Text(.copy)
        }
        .buttonStyle(.pill(.outlined, tint: AppColors.Brand.brand))
      }
      .padding(.top, 2)
    }
  }
}

// MARK: - Preview

#if DEBUG
#Preview {
  PreviewStage {
    WelcomeInviteCard(code: "K7QP2M4XZA", onShowQRCode: {}, onCopy: {})
      .padding()
  }
}
#endif
