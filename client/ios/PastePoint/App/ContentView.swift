//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Logging
import SwiftUI

// MARK: - Root

struct ContentView: View {
  @AppStorage(AppColors.Scheme.storageKey) private var colorSchemeRaw: String = AppColors.Scheme.default
  @EnvironmentObject private var services: AppServices

  private let logger = Logger(label: "ContentView")

  @State private var showSettings = false
  @State private var toasts: [ToastItem] = []

  var body: some View {
    VStack(spacing: 0) {
      ChatNavBar(
        onMenuTap: { showSettings = true },
        onThemeTap: { colorSchemeRaw = AppColors.Scheme.next(after: colorSchemeRaw) },
      )
      Divider()

      if services.localNetworkDenied {
        NetworkPermissionBanner { services.clearLocalNetworkDenied() }
      }

      ChatContainerView()

      ChatInputBar()
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    .background(AppColors.Background.background)
    .preferredColorScheme(AppColors.Scheme.colorScheme(from: colorSchemeRaw))
    .ignoresSafeArea(.keyboard, edges: .bottom)
    .sheet(isPresented: $showSettings) {
      NavigationStack {
        SettingsView {
          showSettings = false
          toasts.append(.success("Private session joined"))
        }
      }
    }
    .onReceive(services.wsService.message) { msg in
      logger.info("User message: \(msg)")
    }
    .onReceive(services.wsService.signalMessage) { sig in
      logger.debug("Signal: \(sig.payload.typeString) | from: \(sig.from) → to: \(sig.to)")
    }
    .onChange(of: services.wsService.isConnected) { wasConnected, connected in
      guard !services.wsService.isLeavingSession else { return }
      if connected, !showSettings {
        toasts.append(wasConnected ? .success("Reconnected") : .success("Connected"))
      } else if wasConnected {
        toasts.append(.warning("Connection lost"))
      }
    }
    .appToast(items: $toasts)
  }
}

// MARK: - Preview

#if DEBUG
#Preview {
  ContentView()
    .environmentObject(AppServices.preview)
}
#endif
