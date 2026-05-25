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
        displayName: stagedFile.name,
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
    case .accept(let payload, let from):
      handleFileAccept(payload: payload, from: from)
    case .received(let payload, let from):
      handleFileReceived(payload: payload, from: from)
    case .decline, .cancelUpload, .cancelDownload:
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

  private func handleFileAccept(payload: FileAcceptPayload, from peer: String) {
    guard
      let idx = activeUploads.firstIndex(where: {
        $0.targetUser == peer && $0.id == payload.fileId
      })
    else {
      logger.warning("file-accept ignored: no upload for \(payload.fileId) → \(peer)")
      return
    }

    let upload = activeUploads[idx]
    logger.info("file-accept received: starting chunk send for \(upload.id) → \(peer)")

    Task.detached { [weak self] in
      await self?.runChunkSendLoop(uploadId: upload.id, targetUser: peer)
    }
  }

  private func runChunkSendLoop(uploadId: String, targetUser: String) async {
    // 1. Snapshot upload metadata from the MainActor.
    let snapshot: (fileURL: URL, fileSize: Int64)? = await MainActor.run {
      guard let upload = activeUploads.first(where: { $0.id == uploadId }) else { return nil }
      return (upload.fileURL, upload.fileSize)
    }

    guard let snapshot else {
      logger.warning("chunk loop: upload \(uploadId) not found")
      return
    }

    // 2. Open the file once.
    let handle: FileHandle
    do {
      handle = try FileHandle(forReadingFrom: snapshot.fileURL)
    } catch {
      logger.error("chunk loop: cannot open \(snapshot.fileURL.path): \(error)")
      return
    }
    defer { try? handle.close() }

    let totalChunks = BinaryChunk.totalChunks(forFileSize: snapshot.fileSize)
    var chunkIndex: UInt32 = 0
    var bytesSent: Int64 = 0

    // 3. Send loop.
    while true {
      let chunkData: Data

      do {
        guard
          let data = try handle.read(upToCount: BinaryChunk.chunkSize),
          !data.isEmpty
        else {
          break // EOF
        }

        chunkData = data
      } catch {
        logger.error("chunk loop: read error: \(error)")
        return
      }

      let encoded = BinaryChunk.encode(
        fileId: uploadId,
        chunkIndex: chunkIndex,
        totalChunks: totalChunks,
        data: chunkData,
      )

      // Back-pressure: poll-retry. `send` returns false when bufferedAmount is
      // above maxBufferedAmount — we sleep briefly and retry until it accepts.
      while true {
        let sent = await MainActor.run {
          signalingService.send(encoded, to: targetUser, isBinary: true)
        }
        if sent { break }
        try? await Task.sleep(nanoseconds: 50_000_000) // 50 ms
      }

      bytesSent += Int64(chunkData.count)
      chunkIndex += 1

      let progressValue = min(1.0, Double(bytesSent) / Double(snapshot.fileSize))
      await MainActor.run {
        if let idx = activeUploads.firstIndex(where: { $0.id == uploadId }) {
          activeUploads[idx].currentOffset = bytesSent
          activeUploads[idx].progress = progressValue
        }
      }
    }

    // 4. Flip phase to .finalizing — bytes shipped, awaiting receiver ack.
    await MainActor.run {
      if let idx = activeUploads.firstIndex(where: { $0.id == uploadId }) {
        activeUploads[idx].phase = .finalizing
      }
    }
    logger.info("chunk loop: finished \(chunkIndex) chunks for \(uploadId) → \(targetUser)")
  }

  private func handleFileReceived(payload: FileReceivedPayload, from peer: String) {
    guard
      let idx = activeUploads.firstIndex(where: {
        $0.targetUser == peer && $0.id == payload.fileId
      })
    else {
      logger.warning("file-received ignored: no upload for \(payload.fileId) ← \(peer)")
      return
    }

    let removed = activeUploads.remove(at: idx)
    logger.info("file-received ack: \(payload.fileId) ← \(peer)")

    // Delete the tmp file only if no other in-flight upload references it.
    // Multiple peer-specific FileUploads share the same source `fileURL` when the
    // user sent one file to many peers; the last one out deletes.
    let stillReferenced = activeUploads.contains { file in
      file.fileURL == removed.fileURL
    }

    if !stillReferenced {
      do {
        try FileManager.default.removeItem(at: removed.fileURL)
        logger.info("removed tmp file: \(removed.fileURL.lastPathComponent)")
      } catch {
        logger.warning("failed to remove tmp file \(removed.fileURL.lastPathComponent): \(error)")
      }
    }
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
