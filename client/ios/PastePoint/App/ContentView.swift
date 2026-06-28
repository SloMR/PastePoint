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

  @State var messages: [ChatMessage] = []
  @State private var showSplash = true
  @State var hasConnectedBefore = false
  @State var showSettings = false
  @State var toasts: [ToastItem] = []
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
  }

  private var chatScreen: some View {
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
          }
          .accessibilityLabel(Text(.switchAppearance))

          Button {
            showSettings = true
          } label: {
            Image(systemName: "gearshape")
          }
          .accessibilityLabel(Text(.settings))
        }
      }
    }
    .background(AppColors.Background.background)
    .preferredColorScheme(AppColors.Scheme.colorScheme(from: colorSchemeRaw))
    .sheet(isPresented: $showSettings) {
      NavigationStack {
        SettingsView {
          showSettings = false
          pendingPrivateJoin = true
        }
      }
    }
  }
}

// MARK: - Preview

#if DEBUG
#Preview {
  ContentView()
    .environmentObject(AppServices.preview)
}
#endif
