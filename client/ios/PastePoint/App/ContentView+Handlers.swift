//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Logging
import SwiftUI

// MARK: - Handlers

extension ContentView {
  func handleSend(_ text: String) -> Bool {
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
      toast.show(.warning(.connecting))
      return false
    }

    let message = ChatMessage(from: from, text: trimmed, isMine: true)
    let reached = services.signalingService.broadcastChat(message)
    guard !reached.isEmpty else {
      toast.show(peerWarning())
      return false
    }

    messages.append(message)
    return true
  }

  func handleSendFiles(_ files: [StagedFile]) -> Bool {
    let peers = Array(services.signalingService.connectedPeers)

    guard !peers.isEmpty else {
      toast.show(peerWarning())
      return false
    }

    for file in files {
      guard file.size > 0 else {
        toast.show(.error(.fileEmptyError(file.name)))
        continue
      }

      Task {
        await services.fileTransferService.sendStagedFile(file, to: peers)
      }
    }
    return true
  }

  /// Universal-link entry: validates an invite URL and joins its private session,
  /// mirroring the manual join flow in `SettingsJoinPrivateView`.
  func handleIncomingURL(_ url: URL) {
    guard LegalConsent.isAccepted else {
      logger.info("Deferring incoming URL until the terms are accepted")
      pendingLegalDeepLink = url
      return
    }

    guard
      let code = AppEnvironment.privateSessionCode(from: url.absoluteString),
      SessionService.isValidSessionCode(code)
    else {
      logger.warning("Ignoring invalid incoming URL")
      toast.show(.error(.invalidSessionCode))
      return
    }

    // Already in this session
    guard services.wsService.currentSessionCode != code else { return }

    logger.info("Joining private session from universal link")
    Task {
      await services.wsService.setupPrivateSession(code)
      guard await services.connectIfPermitted() else {
        toast.show(.error(.localNetworkOffJoin))
        return
      }
      setSettingsVisible(false)
      pendingPrivateJoin = true
      await services.roomService.listRooms()
      await services.userService.getUsername()
    }
  }

  func handleAcceptFile(fromUser: String, fileId: String) {
    Task {
      let result = await services.fileTransferService.acceptFileOffer(fromUser: fromUser, fileId: fileId)

      if result {
        updateFileStatus(fileId: fileId, status: .accepted)
      } else {
        toast.show(.warning(.cantAcceptFile))
      }
    }
  }

  func handleDeclineFile(fromUser: String, fileId: String) {
    Task {
      let result = await services.fileTransferService.declineFileOffer(fromUser: fromUser, fileId: fileId)

      if result {
        updateFileStatus(fileId: fileId, status: .declined)
      } else {
        toast.show(.warning(.cantDeclineFile))
      }
    }
  }

  // TODO: make it safe with return bool to check if the status updated or not
  func updateFileStatus(fileId: String, fileURL: URL? = nil, status: FileTransferStatus) {
    guard let idx = messages.firstIndex(where: { $0.fileTransfer?.fileId == fileId }) else {
      return
    }
    messages[idx].fileTransfer?.status = status
    if let fileURL {
      messages[idx].fileTransfer?.fileURL = fileURL
    }
  }

  func updateOutgoingGroup(groupId: String, status: FileTransferStatus, delivered: Int, total: Int) {
    guard let idx = messages.firstIndex(where: { $0.fileTransfer?.groupId == groupId }) else {
      return
    }

    messages[idx].fileTransfer?.status = status
    messages[idx].fileTransfer?.deliveredCount = delivered
    messages[idx].fileTransfer?.recipientCount = total
  }

  func updatePreview(fileId: String, previewDataUrl: String, previewMime: String?) {
    guard let idx = messages.firstIndex(where: { $0.fileTransfer?.fileId == fileId }) else {
      return
    }
    messages[idx].fileTransfer?.previewDataUrl = previewDataUrl
    messages[idx].fileTransfer?.previewMime = previewMime
  }

  func blockPeer(_ peer: String) {
    guard !peer.isEmpty else { return }

    services.blockService.block(peer)
    messages.removeAll { !$0.isMine && $0.from == peer }

    haptic(.success)
    toast.show(.success(.blockedUserToast(peer)))
  }

  func peerWarning() -> ToastItem {
    // Peers are in the room but no data channel is open yet still (re)connecting.
    if !services.peerDirectory.peers.isEmpty {
      return .warning(.connectingToPeers)
    }
    return .warning(.noPeersConnected)
  }

  func haptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
    UINotificationFeedbackGenerator().notificationOccurred(type)
  }
}
