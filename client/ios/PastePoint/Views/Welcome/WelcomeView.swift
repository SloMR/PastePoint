//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct WelcomeView: View {
  @EnvironmentObject private var services: AppServices
  @EnvironmentObject private var toast: ToastCenter

  private var sessionCode: String? {
    services.wsService.currentSessionCode
  }

  private var isAlone: Bool {
    services.peerDirectory.peers.isEmpty
  }

  var body: some View {
    // Centers the content vertically when it fits, scrolls when it doesn't.
    GeometryReader { geometry in
      ScrollView {
        welcomeContent
          .padding(.vertical, 32)
          .frame(maxWidth: 480)
          .frame(maxWidth: .infinity, minHeight: geometry.size.height)
      }
    }
  }

  private var welcomeContent: some View {
    VStack(alignment: .center, spacing: 20) {
      if sessionCode == nil {
        WelcomeHeader(isAlone: isAlone)
      }

      actions
        .padding(.horizontal, 16)

      if sessionCode == nil {
        VStack(alignment: .leading, spacing: 10) {
          Divider()

          Text(.someoneSentYouACode)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)

          JoinCodeForm()
        }
        .padding(.horizontal, 16)

        Text(.welcomePrivacyNote)
          .font(.caption2)
          .foregroundStyle(.textSecondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 24)
          .padding(.bottom, 8)
      }
    }
  }

  /// How to get another device in, named by where that device is. The action
  /// stays available once peers are here, but drops to a secondary treatment
  /// because sending — not connecting — has become the primary job.
  @ViewBuilder
  private var actions: some View {
    VStack(spacing: 10) {
      if !isAlone, sessionCode == nil {
        Text(.emptyStateConnectedBody)
          .font(.subheadline)
          .foregroundStyle(.textSecondary)
          .multilineTextAlignment(.center)
      }

      if let code = sessionCode {
        privateSession(code: code)
      } else if !isAlone {
        WelcomeCard(
          title: .optionElsewhereTitle,
          message: .optionElsewhereBodyConnected,
          icon: "qrcode",
        ) {
          CreateInviteButton(prominent: false)
        }
      } else {
        WelcomeCard(title: .optionSameWifiTitle, message: .optionSameWifiBody, icon: "users") {
          HStack(spacing: 8) {
            PulsingDot(color: AppColors.Brand.brand, size: 8)

            Text(.lookingForDevices)
              .font(.caption)
              .fontWeight(.semibold)
              .foregroundStyle(AppColors.Brand.brand)
          }
          .padding(.top, 2)
        }

        WelcomeCard(title: .optionElsewhereTitle, message: .optionElsewhereBody, icon: "qrcode") {
          CreateInviteButton()
        }
      }
    }
  }

  private func privateSession(code: String) -> some View {
    VStack(spacing: 16) {
      privateBadge

      Text(.scanToJoinRoom)
        .font(.title2)
        .fontWeight(.bold)
        .foregroundStyle(.textPrimary)
        .multilineTextAlignment(.center)

      SessionShareBlock(
        code: code,
        qrSize: 190,
        caption: .orTypeTheCode,
        shareLabel: .shareLink,
        copyLabel: .copyCode,
      )

      if isAlone {
        HStack(spacing: 8) {
          PulsingDot(color: AppColors.Brand.brand, size: 8)

          Text(.waitingForDevice)
            .font(.caption)
            .foregroundStyle(.textSecondary)
        }
      } else {
        Text(.emptyStateConnectedBody)
          .font(.subheadline)
          .foregroundStyle(.textSecondary)
          .multilineTextAlignment(.center)
      }
    }
  }

  private var privateBadge: some View {
    HStack(spacing: 6) {
      Image("lock.dark")
        .renderingMode(.template)
        .resizable()
        .scaledToFit()
        .frame(width: 13, height: 13)
        .accessibilityHidden(true)

      Text(.privateRoomOnlyCode)
        .font(.caption2)
        .fontWeight(.semibold)
    }
    .foregroundStyle(AppColors.Brand.brand)
    .padding(.vertical, 5)
    .padding(.leading, 8)
    .padding(.trailing, 12)
    .background(AppColors.Brand.brand.opacity(0.1), in: Capsule())
  }

}

// MARK: - Preview

#if DEBUG
#Preview {
  WelcomeView()
    .environmentObject(AppServices.preview)
    .environmentObject(ToastCenter())
}
#endif
