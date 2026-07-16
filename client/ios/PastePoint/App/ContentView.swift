//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Logging
import SwiftUI

// MARK: - Root

struct ContentView: View {
  @AppStorage(AppColors.Scheme.storageKey) private var colorSchemeRaw: String = AppColors.Scheme.default
  @AppStorage(LegalConsent.storageKey) private var acceptedLegalVersion = 0

  @Environment(\.scenePhase) var scenePhase
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.isIPad) private var isIPad

  @EnvironmentObject var toast: ToastCenter
  @EnvironmentObject var services: AppServices

  let logger = Logger(label: "ContentView")

  @State private var showSplash = true
  @State private var splashStart = Date()
  @State private var splashDismissing = false

  @State var messages: [ChatMessage] = []
  @State var hasConnectedBefore = false
  @State var showSettings = false
  @State var pendingPrivateJoin = false
  @State var suppressNextConnectToast = false

  private let splashCeiling: Double = 5.0
  private let splashFloor: Double = 1.4

  @ViewBuilder
  private var connectionBanner: some View {
    if services.localNetworkDenied {
      NetworkPermissionBanner { services.clearLocalNetworkDenied() }
    } else if let reconnect = services.wsService.reconnectState {
      ChatServerReconnectBanner(attempt: reconnect.attempt, nextAttemptDate: reconnect.nextAttemptDate)
    } else if services.connectionWarningMonitor.showWarning {
      ChatConnectionWarningBanner {
        services.connectionWarningMonitor.dismiss()
      }
    }
  }

  private var isPrivateRoom: Bool {
    services.wsService.currentSessionCode != nil
  }

  private var needsLegalConsent: Bool {
    acceptedLegalVersion < LegalConsent.currentVersion
  }

  var body: some View {
    ZStack {
      chatScreen.chatEventHandlers(self)

      if showSplash {
        SplashView()
          .transition(.opacity)
          .zIndex(1)
          .onReceive(services.wsService.didConnect) { dismissSplash() }
          .task {
            if services.wsService.isConnected { dismissSplash() }
          }
          .task {
            try? await Task.sleep(for: .seconds(splashCeiling))
            dismissSplash()
          }
      }

      if needsLegalConsent, !showSplash {
        LegalGateView {
          withAnimation { acceptedLegalVersion = LegalConsent.currentVersion }
        }
        .transition(.opacity)
        .zIndex(2)
        .preferredColorScheme(AppColors.Scheme.colorScheme(from: colorSchemeRaw))
      }
    }
    .fullScreenCover(isPresented: forcedUpdatePresented) {
      if case let .required(url) = services.updateService.recommendation {
        UpdateView(kind: .required, storeURL: url)
      }
    }
    .sheet(isPresented: optionalUpdatePresented) {
      if case let .optional(latest, url) = services.updateService.recommendation {
        UpdateView(kind: .optional, storeURL: url, latest: latest)
      }
    }
  }

  // MARK: - Splash dismissal

  private func dismissSplash() {
    guard showSplash, !splashDismissing else { return }
    splashDismissing = true

    let remaining = splashFloor - Date().timeIntervalSince(splashStart)
    guard remaining > 0 else {
      withAnimation(.easeOut(duration: 0.4)) { showSplash = false }
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + remaining) {
      withAnimation(.easeOut(duration: 0.4)) { showSplash = false }
    }
  }

  // MARK: - Update presentation

  private var forcedUpdatePresented: Binding<Bool> {
    Binding(
      get: {
        guard !showSplash else { return false }
        if case .required = services.updateService.recommendation { return true }
        return false
      },
      set: { _ in },
    )
  }

  private var optionalUpdate: (latest: String, url: URL)? {
    if case let .optional(latest, url) = services.updateService.recommendation {
      return (latest, url)
    }
    return nil
  }

  private var optionalUpdatePresented: Binding<Bool> {
    Binding(
      get: { !showSplash && optionalUpdate != nil },
      set: { presented in if !presented { services.updateService.dismissOptional() } },
    )
  }

  // MARK: - Chat Screen

  private var chatScreen: some View {
    HStack(spacing: 0) {
      // Leading docked panel on iPad
      if isIPad, showSettings {
        settingsPanel
          .transition(.move(edge: .leading))
      }

      NavigationStack {
        ChatContainerView(
          messages: messages,
          onAcceptFile: handleAcceptFile,
          onDeclineFile: handleDeclineFile,
          onBlock: blockPeer,
        )
        .simultaneousGesture(
          TapGesture().onEnded {
            UIApplication.shared.sendAction(
              #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil,
            )
          },
        )
        .safeAreaInset(edge: .top, spacing: 0) {
          connectionBanner
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
          ChatInputBar(
            onSend: handleSend,
            onSendFiles: handleSendFiles,
            hasConnectedPeers: !services.signalingService.connectedPeers.isEmpty,
          )
          .padding(.horizontal, 8)
          .padding(.top, 4)
          .padding(.bottom, 0)
          .frame(maxWidth: .infinity)
          .background {
            AppColors.Background.background
              .ignoresSafeArea(edges: .bottom)
          }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .principal) {
            HStack(spacing: 6) {
              Image(isPrivateRoom ? (colorScheme == .dark ? "lock.light" : "lock.dark") : "users")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(.textPrimary)

              Text(isPrivateRoom ? .privateRoom : .publicRoom)
                .font(.headline)
                .foregroundStyle(.textPrimary)
            }
          }

          ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
              colorSchemeRaw = AppColors.Scheme.next(after: colorSchemeRaw)
            } label: {
              Image(systemName: colorScheme == .dark ? "sun.max.fill" : "moon")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
            }
            .accessibilityLabel(Text(.switchAppearance))

            Button {
              setSettingsVisible(!showSettings)
            } label: {
              Image(systemName: "gearshape")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
            }
            .accessibilityLabel(Text(.settings))
          }
        }
      }
    }
    .background(AppColors.Background.background)
    .preferredColorScheme(AppColors.Scheme.colorScheme(from: colorSchemeRaw))
    .sheet(isPresented: settingsSheetPresented) {
      NavigationStack {
        SettingsView(
          onSessionJoin: {
            showSettings = false
            pendingPrivateJoin = true
          },
          onBlock: blockPeer,
        )
      }
    }
  }

  // MARK: - Settings presentation

  /// Shows/hides settings inside one animation transaction (gear toggle + panel close).
  func setSettingsVisible(_ visible: Bool) {
    withAnimation(.easeInOut(duration: 0.25)) {
      showSettings = visible
    }
  }

  /// Compact widths present settings as a sheet instead of the docked panel.
  private var settingsSheetPresented: Binding<Bool> {
    Binding(
      get: { showSettings && !isIPad },
      set: { showSettings = $0 },
    )
  }

  private var settingsPanel: some View {
    HStack(spacing: 0) {
      NavigationStack {
        SettingsView(
          onClose: { setSettingsVisible(false) },
          onSessionJoin: {
            setSettingsVisible(false)
            pendingPrivateJoin = true
          },
          onBlock: blockPeer,
        )
      }
      .frame(width: 320)

      Divider()
        .ignoresSafeArea()
    }
  }
}

// MARK: - Preview

#if DEBUG
#Preview {
  ContentView()
    .environmentObject(AppServices.preview)
    .environmentObject(ToastCenter())
}
#endif
