//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Logging
import SwiftUI

// MARK: - Root

struct ContentView: View {
  @AppStorage(AppColors.Scheme.storageKey) private var colorSchemeRaw: String = AppColors.Scheme.default
  @EnvironmentObject var services: AppServices
  @Environment(\.scenePhase) var scenePhase
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.isIPad) private var isIPad

  let logger = Logger(label: "ContentView")

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

  @EnvironmentObject var toast: ToastCenter

  @State var messages: [ChatMessage] = []
  @State private var showSplash = true
  @State var hasConnectedBefore = false
  @State var showSettings = false
  @State var pendingPrivateJoin = false
  @State var suppressNextConnectToast = false

  private var isPrivateRoom: Bool {
    services.wsService.currentSessionCode != nil
  }

  var body: some View {
    ZStack {
      chatScreen.chatEventHandlers(self)

      if showSplash {
        SplashView {
          withAnimation(.easeOut(duration: 0.4)) {
            showSplash = false
          }
        }
        .transition(.opacity)
        .zIndex(1)
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
        SettingsView {
          showSettings = false
          pendingPrivateJoin = true
        }
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
