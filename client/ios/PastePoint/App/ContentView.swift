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

  @State private var messages: [ChatMessage] = []
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

      ChatContainerView(
        messages: messages,
        onAcceptFile: handleAcceptFile,
        onDeclineFile: handleDeclineFile,
      )
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      ChatInputBar(onSend: handleSend, onSendFiles: handleSendFiles)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background {
          AppColors.Background.background
            .ignoresSafeArea(edges: .bottom)
        }
    }
    .background(AppColors.Background.background)
    .preferredColorScheme(AppColors.Scheme.colorScheme(from: colorSchemeRaw))
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
    .onReceive(services.signalingService.chatMessages) { message in
      messages.append(message)
    }
    .onReceive(services.fileTransferService.attachmentMessages) { message in
      messages.append(message)
    }
    .onChange(of: services.roomService.currentRoom) {
      messages = []
    }
    .onChange(of: services.wsService.currentSessionCode) {
      messages = []
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

  private func handleSend(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }

    let from: String = {
#if DEBUG
      if AppBuildInfo.isXcodePreview {
        let members = services.roomService.members
        if !members.isEmpty {
          return members[messages.count % members.count]
        }
      }
#endif
      return services.userService.user
    }()

    guard !from.isEmpty else {
      toasts.append(.warning("Connecting…"))
      return false
    }

    let message = ChatMessage(from: from, text: trimmed)
    let reached = services.signalingService.broadcastChat(message)
    guard !reached.isEmpty else {
      toasts.append(.warning("No peers connected"))
      return false
    }

    messages.append(message)
    return true
  }

  private func handleSendFiles(_ files: [StagedFile]) -> Bool {
    let peers = Array(services.signalingService.connectedPeers)

    guard !peers.isEmpty else {
      toasts.append(.warning("No peers connected"))
      return false
    }

    // TODO: find a away to improve this
    for peer in peers {
      for file in files {
        Task {
          await services.fileTransferService.prepareFileForSending(
            stagedFile: file,
            targetUser: peer,
          )
        }
      }
    }
    return true
  }

  private func handleAcceptFile(fromUser: String, fileId: String) {
    Task {
      let result = await services.fileTransferService.acceptFileOffer(fromUser: fromUser, fileId: fileId)

      if result {
        updateFileStatus(fileId: fileId, status: .accepted)
      } else {
        toasts.append(.warning("Couldn't accept file"))
      }
    }
  }

  private func handleDeclineFile(fromUser: String, fileId: String) {
    Task {
      let result = await services.fileTransferService.declineFileOffer(fromUser: fromUser, fileId: fileId)

      if result {
        updateFileStatus(fileId: fileId, status: .declined)
      } else {
        toasts.append(.warning("Couldn't decline file"))
      }
    }
  }

  // TODO: make it safe with return bool to check if the status updated or not
  private func updateFileStatus(fileId: String, status: FileTransferStatus) {
    guard let idx = messages.firstIndex(where: { $0.fileTransfer?.fileId == fileId }) else {
      return
    }
    messages[idx].fileTransfer?.status = status
  }
}

// MARK: - Preview

#if DEBUG
#Preview {
  ContentView()
    .environmentObject(AppServices.preview)
}
#endif
