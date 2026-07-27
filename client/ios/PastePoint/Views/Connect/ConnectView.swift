//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct ConnectView: View {
  @EnvironmentObject private var services: AppServices
  @EnvironmentObject private var toast: ToastCenter

  var onSessionJoin: (() -> Void)?

  private var sessionCode: String? {
    services.wsService.currentSessionCode
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if let code = sessionCode {
        shareSection(code: code)
      } else {
        createSection
      }

      Divider()

      VStack(alignment: .leading, spacing: 10) {
        Text(.joiningSomeoneElse)
          .font(.caption)
          .fontWeight(.semibold)
          .foregroundStyle(.textSecondary)

        JoinCodeForm(onSessionJoin: onSessionJoin)
      }
    }
    .padding(24)
    .sheetContainer(title: .connectDeviceTitle)
  }

  // MARK: - Share

  private func shareSection(code: String) -> some View {
    VStack(spacing: 12) {
      QRCodeView(text: AppEnvironment.privateSessionUrl(sessionCode: code), size: 180)
        .padding(12)
        .background(Color(.white), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)

      Text(code)
        .font(.system(.body, design: .monospaced).weight(.medium))
        .foregroundStyle(.textPrimary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.inputBackground, in: RoundedRectangle(cornerRadius: 8))

      HStack(spacing: 8) {
        ShareLink(item: AppEnvironment.privateSessionUrl(sessionCode: code)) {
          Text(.share)
        }
        .buttonStyle(.pill(tint: AppColors.Brand.brand))

        Button {
          UIPasteboard.general.string = code
          toast.show(.success(.codeCopied))
        } label: {
          Text(.copy)
        }
        .buttonStyle(.pill(.outlined, tint: AppColors.Brand.brand))
      }
    }
  }

  // MARK: - Create

  private var createSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(
        services.peerDirectory.peers.isEmpty
          ? .optionElsewhereBody
          : .optionElsewhereBodyConnected,
      )
      .font(.caption)
      .foregroundStyle(.textSecondary)
      .fixedSize(horizontal: false, vertical: true)

      CreateInviteButton()
    }
  }

}

// MARK: - Preview

#if DEBUG
#Preview {
  ConnectView()
    .environmentObject(AppServices.preview)
    .environmentObject(ToastCenter())
}
#endif
