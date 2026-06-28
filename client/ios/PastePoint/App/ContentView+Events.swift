//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Logging
import SwiftUI

// MARK: - Event Wiring

/// Subscribes `content` to the service publishers and scene-driven reactions.
///
/// Takes the owning `ContentView` so the closures can reach its handlers and
/// `@State` directly — `@State`'s setter is `nonmutating` and writes to
/// SwiftUI-managed storage, so mutating through the passed-in value updates the
/// live view. Kept out of `chatScreen` so the body stays pure layout.
private struct ChatEventHandlers: ViewModifier {
  let owner: ContentView

  func body(content: Content) -> some View {
    connectionHandlers(fileTransferHandlers(messageHandlers(content)))
  }

  // MARK: - Incoming messages

  private func messageHandlers(_ content: some View) -> some View {
    content
      .onReceive(owner.services.wsService.message) { msg in
        owner.logger.info("User message: \(msg)")
      }
      .onReceive(owner.services.wsService.signalMessage) { sig in
        owner.logger.debug("Signal: \(sig.payload.typeString) | from: \(sig.from) → to: \(sig.to)")
      }
      .onReceive(owner.services.signalingService.chatMessages) { message in
        owner.messages.append(message)
      }
      .onReceive(owner.services.fileTransferService.attachmentMessages) { message in
        owner.messages.append(message)
      }
      .onReceive(owner.services.fileTransferService.outgoingAttachment) { message in
        owner.messages.append(message)
      }
  }

  // MARK: - File transfer

  private func fileTransferHandlers(_ content: some View) -> some View {
    content
      .onReceive(owner.services.fileTransferService.downloadCompleted) { fileId, fileURL in
        owner.updateFileStatus(fileId: fileId, fileURL: fileURL, status: .completed)
        owner.haptic(.success)
      }
      .onReceive(owner.services.fileTransferService.outgoingGroupStatus) { update in
        owner.updateOutgoingGroup(groupId: update.groupId, status: update.status, delivered: update.delivered, total: update.total)
      }
      .onReceive(owner.services.fileTransferService.attachmentPreviewUpdated) { update in
        owner.updatePreview(fileId: update.fileId, previewDataUrl: update.previewDataUrl, previewMime: update.previewMime)
      }
      .onReceive(owner.services.fileTransferService.fileTransferCancelled) { fileId in
        owner.updateFileStatus(fileId: fileId, status: .cancelled)
      }
      .onReceive(owner.services.fileTransferService.fileTransferFailed) { fileId, reason in
        owner.updateFileStatus(fileId: fileId, status: .failed)
        owner.haptic(.error)
        owner.toast.show(.error(failureMessage(for: reason)))
      }
  }

  private func failureMessage(for reason: FileTransferFailureReason) -> LocalizedStringResource {
    switch reason {
    case .integrity: .fileCorrupted
    case .assembly: .fileAssemblyFailed
    case .noHash: .fileRejectedNoHash
    case .sendHashFailed: .fileSendHashFailed
    case .stalled: .fileTransferStalled
    case .saveFailed: .fileSaveFailed
    case .photosPermissionDenied: .photosPermissionDenied
    }
  }

  // MARK: - Connection

  private func connectionHandlers(_ content: some View) -> some View {
    content
      .onReceive(owner.services.wsService.sessionRejected) {
        owner.pendingPrivateJoin = false
        owner.suppressNextConnectToast = true
        owner.toast.show(.warning(.sessionJoinFailed))
      }
      .onReceive(owner.services.wsService.didConnect) {
        handleDidConnect()
      }
      .onChange(of: owner.services.roomService.currentRoom) {
        owner.messages = []
      }
      .onChange(of: owner.services.wsService.currentSessionCode) {
        owner.messages = []
      }
      .onChange(of: owner.services.wsService.isConnected) { wasConnected, connected in
        // Only surface unexpected drops while active; ignore background/manual teardown.
        guard wasConnected, !connected else { return }
        guard !owner.services.wsService.isLeavingSession, owner.scenePhase == .active else { return }
        owner.toast.show(.warning(.connectionLost))
      }
  }

  private func handleDidConnect() {
    let wasReconnect = owner.hasConnectedBefore
    let wasPrivateJoin = owner.pendingPrivateJoin
    owner.hasConnectedBefore = true
    owner.pendingPrivateJoin = false // consume regardless of branch so it can't leak into a later reconnect

    if owner.suppressNextConnectToast {
      owner.suppressNextConnectToast = false
      return
    }
    guard !owner.showSettings else { return }

    if wasPrivateJoin {
      owner.toast.show(.success(.privateSessionJoined))
    } else {
      owner.toast.show(wasReconnect ? .success(.reconnected) : .success(.connected))
    }
  }
}

extension View {
  /// Applies the chat event subscriptions, passing the owning view so the
  /// handlers stay on `ContentView`. See `ChatEventHandlers`.
  func chatEventHandlers(_ owner: ContentView) -> some View {
    modifier(ChatEventHandlers(owner: owner))
  }
}
