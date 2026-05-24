//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Combine
import Foundation
import Logging

@MainActor
final class FileTransferService: ObservableObject {
  private let logger = Logger(label: "FileTransferService")
  private let signalingService: SignalingService
  private let userService: UserService

  @Published private(set) var activeUploads: [FileUpload] = []
  @Published private(set) var activeDownloads: [FileDownload] = []
  @Published private(set) var incomingFileOffers: [FileDownload] = []

  let attachmentMessages = PassthroughSubject<ChatMessage, Never>()
  private var cancellables: Set<AnyCancellable> = []

  init(signalingService: SignalingService, userService: UserService) {
    self.signalingService = signalingService
    self.userService = userService

    signalingService.fileEvent
      .sink { [weak self] event in
        Task { @MainActor in
          self?.handleFileEvent(event)
        }
      }
      .store(in: &cancellables)
  }

  @discardableResult
  func prepareFileForSending(stagedFile: StagedFile, targetUser: String) async -> Bool {
    await userService.waitForUsername()
    let sender = userService.user

    let fileId = UUID().uuidString
    let offer = FileOfferPayload(
      fileId: fileId,
      fileName: stagedFile.name,
      fileSize: stagedFile.size,
      fromUser: sender,
      fileHash: nil,
      previewDataUrl: nil,
      previewMime: nil,
    )

    let data: Data
    do {
      data = try DataChannelMessage.encodeFileOffer(offer)
    } catch {
      logger.error("encodeFileOffer failed for \(stagedFile.name): \(error)")
      return false
    }

    guard signalingService.send(data, to: targetUser) else {
      logger.warning("send failed for file-offer \(fileId) to \(targetUser)")
      return false
    }

    activeUploads.append(
      FileUpload(
        id: fileId,
        fileURL: stagedFile.url,
        fileSize: stagedFile.size,
        targetUser: targetUser,
        currentOffset: 0,
        progress: 0,
        phase: .sending,
      ),
    )
    logger.info("file-offer sent: \(stagedFile.name) (\(fileId)) → \(targetUser)")
    return true
  }

  private func handleFileEvent(_ event: FileChannelEvent) {
    switch event {
    case .offer(let payload, let from):
      receiveFileOffer(payload: payload, from: from)
    case .accept, .decline, .cancelUpload, .cancelDownload, .received:
      break
    }
  }

  private func receiveFileOffer(payload: FileOfferPayload, from peer: String) {
    if incomingFileOffers.contains(where: { $0.id == payload.fileId }) {
      logger.info("ignored duplicate file-offer \(payload.fileId)")
      return
    }

    let download = FileDownload(
      id: payload.fileId,
      fileName: payload.fileName,
      fileSize: payload.fileSize,
      fromUser: peer,
      totalChunks: 0,
      receivedSize: 0,
      receivedChunkURLs: [:],
      progress: 0,
      isAccepted: false,
      expectedHash: payload.fileHash,
    )
    incomingFileOffers.append(download)

    let fileTransfer = FileTransferData(
      fileId: payload.fileId,
      fileName: payload.fileName,
      fileSize: payload.fileSize,
      fromUser: peer,
      status: .pending,
    )
    let message = ChatMessage(
      from: peer,
      text: payload.fileName,
      type: .attachment,
      fileTransfer: fileTransfer,
    )

    attachmentMessages.send(message)
    logger.info("received file-offer: \(payload.fileName) (\(payload.fileId)) from \(peer)")
  }

  @discardableResult
  func acceptFileOffer(fromUser: String, fileId: String) async -> Bool {
    guard let idx = incomingFileOffers.firstIndex(where: { $0.id == fileId }) else {
      logger.warning("no offer for \(fileId)")
      return false
    }

    let data: Data
    do {
      data = try DataChannelMessage.encodeFileAccept(FileAcceptPayload(fileId: fileId))
    } catch {
      logger.error("encodeFileAccept failed: \(error)")
      return false
    }

    guard signalingService.send(data, to: fromUser) else {
      logger.warning("send failed for file-accept \(fileId) to \(fromUser)")
      return false
    }

    var download = incomingFileOffers.remove(at: idx)
    download.isAccepted = true
    activeDownloads.append(download)

    logger.info("file-accept sent: \(fileId) → \(fromUser)")
    return true
  }

  @discardableResult
  func declineFileOffer(fromUser: String, fileId: String) async -> Bool {
    guard let idx = incomingFileOffers.firstIndex(where: { $0.id == fileId }) else {
      logger.warning("no offer for \(fileId)")
      return false
    }

    let data: Data
    do {
      data = try DataChannelMessage.encodeFileDecline(FileDeclinePayload(fileId: fileId))
    } catch {
      logger.error("encodeFileDecline failed: \(error)")
      return false
    }

    guard signalingService.send(data, to: fromUser) else {
      logger.warning("send failed for file-decline \(fileId) to \(fromUser)")
      return false
    }

    incomingFileOffers.remove(at: idx)
    logger.info("file-decline sent: \(fileId) → \(fromUser)")
    return true
  }
}
