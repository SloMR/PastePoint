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
  @Environment(\.scenePhase) private var scenePhase

  private let logger = Logger(label: "ContentView")

  @State private var messages: [ChatMessage] = []
  @State private var hasConnectedBefore = false
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
      ChatInputBar(
        onSend: handleSend,
        onSendFiles: handleSendFiles,
        hasConnectedPeers: !services.signalingService.connectedPeers.isEmpty,
      )
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
    .onReceive(services.fileTransferService.outgoingAttachment) { message in
      messages.append(message)
    }
    .onReceive(services.fileTransferService.downloadCompleted) { fileId, fileURL in
      updateFileStatus(fileId: fileId, fileURL: fileURL, status: .completed)
    }
    .onReceive(services.fileTransferService.fileTransferCancelled) { fileId in
      updateFileStatus(fileId: fileId, status: .cancelled)
    }
    .onReceive(services.wsService.didConnect) {
      guard !showSettings else {
        hasConnectedBefore = true
        return
      }
      toasts.append(hasConnectedBefore ? .success("Reconnected") : .success("Connected"))
      hasConnectedBefore = true
    }
    .onChange(of: services.roomService.currentRoom) {
      messages = []
    }
    .onChange(of: services.wsService.currentSessionCode) {
      messages = []
    }
    .onChange(of: services.wsService.isConnected) { wasConnected, connected in
      // Only surface unexpected drops while active; ignore background/manual teardown.
      guard wasConnected, !connected else { return }
      guard !services.wsService.isLeavingSession, scenePhase == .active else { return }
      toasts.append(.warning("Connection lost"))
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

    let message = ChatMessage(from: from, text: trimmed, isMine: true)
    let reached = services.signalingService.broadcastChat(message)
    guard !reached.isEmpty else {
      toasts.append(peerWarning())
      return false
    }

    messages.append(message)
    return true
  }

  private func handleSendFiles(_ files: [StagedFile]) -> Bool {
    let peers = Array(services.signalingService.connectedPeers)

    guard !peers.isEmpty else {
      toasts.append(peerWarning())
      return false
    }

    let sender = services.userService.user
    for file in files {
      let fileTransfer = FileTransferData(
        fileId: UUID().uuidString,
        fileName: file.name,
        fileSize: file.size,
        fromUser: sender,
        status: .pending,
      )
      messages.append(
        ChatMessage(
          from: sender,
          text: file.name,
          type: .attachment,
          fileTransfer: fileTransfer,
          isMine: true,
        ),
      )
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
  private func updateFileStatus(fileId: String, fileURL: URL? = nil, status: FileTransferStatus) {
    guard let idx = messages.firstIndex(where: { $0.fileTransfer?.fileId == fileId }) else {
      return
    }
    messages[idx].fileTransfer?.status = status
    if let fileURL {
      messages[idx].fileTransfer?.fileURL = fileURL
    }
  }

  private func peerWarning() -> ToastItem {
    // Peers are in the room but no data channel is open yet still (re)connecting.
    if !services.peerDirectory.peers.isEmpty {
      return .warning("Connecting to peers… try again in a moment")
    }
    return .warning("No peers connected")
  }
}

// MARK: - Preview

#if DEBUG
#Preview {
  ContentView()
    .environmentObject(AppServices.preview)
}
#endif
