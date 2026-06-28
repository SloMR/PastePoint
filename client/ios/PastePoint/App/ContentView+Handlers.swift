//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

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
