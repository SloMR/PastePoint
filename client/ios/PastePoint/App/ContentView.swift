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
  @Environment(\.colorScheme) private var colorScheme

  private let logger = Logger(label: "ContentView")

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

  @State private var messages: [ChatMessage] = []
  @State private var hasConnectedBefore = false
  @State private var showSettings = false
  @State private var toasts: [ToastItem] = []
  @State private var pendingPrivateJoin = false
  @State private var suppressNextConnectToast = false

  var body: some View {
    NavigationStack {
      ChatContainerView(
        messages: messages,
        onAcceptFile: handleAcceptFile,
        onDeclineFile: handleDeclineFile,
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
      haptic(.success)
    }
    .onReceive(services.fileTransferService.outgoingGroupStatus) { update in
      updateOutgoingGroup(groupId: update.groupId, status: update.status, delivered: update.delivered, total: update.total)
    }
    .onReceive(services.fileTransferService.attachmentPreviewUpdated) { update in
      updatePreview(fileId: update.fileId, previewDataUrl: update.previewDataUrl, previewMime: update.previewMime)
    }
    .onReceive(services.fileTransferService.fileTransferCancelled) { fileId in
      updateFileStatus(fileId: fileId, status: .cancelled)
    }
    .onReceive(services.fileTransferService.fileTransferFailed) { fileId, reason in
      updateFileStatus(fileId: fileId, status: .failed)
      haptic(.error)
      switch reason {
      case .integrity:
        toasts.append(.error(.fileCorrupted))
      case .assembly:
        toasts.append(.error(.fileAssemblyFailed))
      case .noHash:
        toasts.append(.error(.fileRejectedNoHash))
      case .sendHashFailed:
        toasts.append(.error(.fileSendHashFailed))
      case .stalled:
        toasts.append(.error(.fileTransferStalled))
      case .saveFailed:
        toasts.append(.error(.fileSaveFailed))
      case .photosPermissionDenied:
        toasts.append(.error(.photosPermissionDenied))
      }
    }
    .onReceive(services.wsService.sessionRejected) {
      pendingPrivateJoin = false
      suppressNextConnectToast = true
      toasts.append(.warning(.sessionJoinFailed))
    }
    .onReceive(services.wsService.didConnect) {
      let wasReconnect = hasConnectedBefore
      let wasPrivateJoin = pendingPrivateJoin
      hasConnectedBefore = true
      pendingPrivateJoin = false // consume regardless of branch so it can't leak into a later reconnect

      if suppressNextConnectToast {
        suppressNextConnectToast = false
        return
      }
      guard !showSettings else { return }

      if wasPrivateJoin {
        toasts.append(.success(.privateSessionJoined))
      } else {
        toasts.append(wasReconnect ? .success(.reconnected) : .success(.connected))
      }
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
      toasts.append(.warning(.connectionLost))
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
      toasts.append(.warning(.connecting))
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

    for file in files {
      guard file.size > 0 else {
        toasts.append(.error(.fileEmptyError(file.name)))
        continue
      }

      Task {
        await services.fileTransferService.sendStagedFile(file, to: peers)
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
        toasts.append(.warning(.cantAcceptFile))
      }
    }
  }

  private func handleDeclineFile(fromUser: String, fileId: String) {
    Task {
      let result = await services.fileTransferService.declineFileOffer(fromUser: fromUser, fileId: fileId)

      if result {
        updateFileStatus(fileId: fileId, status: .declined)
      } else {
        toasts.append(.warning(.cantDeclineFile))
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

  private func updateOutgoingGroup(groupId: String, status: FileTransferStatus, delivered: Int, total: Int) {
    guard let idx = messages.firstIndex(where: { $0.fileTransfer?.groupId == groupId }) else {
      return
    }

    messages[idx].fileTransfer?.status = status
    messages[idx].fileTransfer?.deliveredCount = delivered
    messages[idx].fileTransfer?.recipientCount = total
  }

  private func updatePreview(fileId: String, previewDataUrl: String, previewMime: String?) {
    guard let idx = messages.firstIndex(where: { $0.fileTransfer?.fileId == fileId }) else {
      return
    }
    messages[idx].fileTransfer?.previewDataUrl = previewDataUrl
    messages[idx].fileTransfer?.previewMime = previewMime
  }

  private func peerWarning() -> ToastItem {
    // Peers are in the room but no data channel is open yet still (re)connecting.
    if !services.peerDirectory.peers.isEmpty {
      return .warning(.connectingToPeers)
    }
    return .warning(.noPeersConnected)
  }

  private func haptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
    UINotificationFeedbackGenerator().notificationOccurred(type)
  }
}

// MARK: - Preview

#if DEBUG
#Preview {
  ContentView()
    .environmentObject(AppServices.preview)
}
#endif
