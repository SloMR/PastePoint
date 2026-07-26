//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct WelcomeView: View {
  @EnvironmentObject private var services: AppServices
  @EnvironmentObject private var toast: ToastCenter

  @State private var isStarting = false
  @State private var isQRCodeSheetPresented = false

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
    .sheet(isPresented: $isQRCodeSheetPresented) {
      SettingsQRCodeView()
    }
  }

  private var welcomeContent: some View {
    VStack(alignment: .center, spacing: 20) {
      WelcomeHeader(isPrivate: sessionCode != nil, isAlone: isAlone)

      actions
        .padding(.horizontal, 16)

      WelcomeFeatureGrid()
        .padding(.horizontal, 16)

      HStack(spacing: 8) {
        ForEach(0..<3, id: \.self) { _ in
          Circle().fill(.brand.opacity(0.47)).frame(width: 8, height: 8)
        }
      }
      .padding(.bottom, 8)
    }
  }

  /// How to get another device in, named by where that device is. The action
  /// stays available once peers are here, but drops to a secondary treatment
  /// because sending — not connecting — has become the primary job.
  @ViewBuilder
  private var actions: some View {
    VStack(spacing: 10) {
      if !isAlone {
        Text(.emptyStateConnectedBody)
          .font(.subheadline)
          .foregroundStyle(.textSecondary)
          .multilineTextAlignment(.center)
      }

      if let code = sessionCode {
        WelcomeInviteCard(
          code: code,
          onShowQRCode: { isQRCodeSheetPresented = true },
          onCopy: { copy(code) },
        )
      } else if !isAlone {
        WelcomeCard(title: .optionElsewhereTitle, message: .optionElsewhereBodyConnected) {
          WelcomeConnectButton(label: .connectADevice, prominent: false, isBusy: isStarting) {
            Task { await startPrivateSession() }
          }
        }
      } else {
        WelcomeCard(title: .optionSameWifiTitle, message: .optionSameWifiBody)
        WelcomeCard(title: .optionElsewhereTitle, message: .optionElsewhereBody) {
          WelcomeConnectButton(label: .connectADevice, prominent: true, isBusy: isStarting) {
            Task { await startPrivateSession() }
          }
        }
      }
    }
  }

  private func copy(_ code: String) {
    UIPasteboard.general.string = code
    toast.show(.success(.codeCopied))
  }

  private func startPrivateSession() async {
    isStarting = true
    defer { isStarting = false }
    do {
      log.info("Connect a device tapped from welcome screen")
      try await services.sessionService.preparePrivateSession()
      guard await services.connectIfPermitted() else {
        toast.show(.error(.localNetworkOffStart))
        return
      }
      toast.show(.success(.privateSessionStarted))
    } catch {
      log.error("Cannot get the session code \(error)")
      toast.show(.error(.startPrivateFailed))
    }
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
