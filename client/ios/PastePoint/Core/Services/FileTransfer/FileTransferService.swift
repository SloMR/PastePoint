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
  let downloadCompleted = PassthroughSubject<(fileId: String, fileURL: URL), Never>()
  let fileTransferCancelled = PassthroughSubject<String, Never>()

  private var pendingChunkIndices: [String: Set<Int>] = [:]
  private var uploadTasks: [String: Task<Void, Never>] = [:]
  private var knownPeers: Set<String> = []
  private var cancellables: Set<AnyCancellable> = []

  init(signalingService: SignalingService, userService: UserService, peerDirectory: PeerDirectory) {
    self.signalingService = signalingService
    self.userService = userService

    signalingService.fileEvent
      .sink { [weak self] event in
        Task { @MainActor in
          self?.handleFileEvent(event)
        }
      }
      .store(in: &cancellables)

    signalingService.chunkReceived
      .sink { [weak self] parsed, from in
        Task { @MainActor in
          await self?.handleChunk(parsed, from: from)
        }
      }
      .store(in: &cancellables)

    peerDirectory.$peers
      .sink { [weak self] peers in
        Task { @MainActor in
          self?.reconcilePeers(peers)
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
    case .decline(let payload, let from):
      handleFileDecline(fileId: payload.fileId, from: from)
    case .cancelDownload(let payload, let from):
      handleFileDownloadCancellation(fileId: payload.fileId, from: from)
    case .cancelUpload(let payload, let from):
      handleFileUploadCancellation(fileId: payload.fileId, from: from)
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

    let task = Task.detached { [weak self] in
      guard let self else { return }
      await self.runChunkSendLoop(uploadId: upload.id, targetUser: peer)
    }
    uploadTasks[upload.id] = task
  }

  private nonisolated func runChunkSendLoop(uploadId: String, targetUser: String) async {
    defer { Task { @MainActor [weak self] in self?.uploadTasks[uploadId] = nil } }

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
      if Task.isCancelled {
        logger.info("chunk loop cancelled for \(uploadId) → \(targetUser)")
        return
      }

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
        if Task.isCancelled {
          logger.info("chunk loop cancelled (back-pressure wait) for \(uploadId)")
          return
        }
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

  private func handleChunk(_ parsed: ParsedChunk, from peer: String) async {
    guard
      let idx = activeDownloads.firstIndex(where: { file in
        file.id == parsed.fileId && file.fromUser == peer
      })
    else {
      // No accepted download for this chunk — offer not accepted, or already done.
      return
    }

    guard parsed.isValid else {
      // TODO: corrupted chunk (CRC mismatch). v1 drops + logs; could request resend.
      logger.warning("invalid chunk \(parsed.chunkIndex) for \(parsed.fileId), dropping")
      return
    }

    let chunkIndex = Int(parsed.chunkIndex)

    // Atomic reserve (no await before this returns): skip if already committed
    // or already being written.
    if activeDownloads[idx].receivedChunkURLs[chunkIndex] != nil { return }
    if pendingChunkIndices[parsed.fileId]?.contains(chunkIndex) == true { return }
    pendingChunkIndices[parsed.fileId, default: []].insert(chunkIndex)

    // Write off the main actor.
    let dir = chunkDirectory(for: parsed.fileId)
    let chunkURL = dir.appendingPathComponent("\(chunkIndex)")
    let data = parsed.data

    let didWrite = await Task.detached {
      do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: chunkURL)
        return true
      } catch {
        return false
      }
    }.value

    // Back on MainActor. Clear the reservation.
    pendingChunkIndices[parsed.fileId]?.remove(chunkIndex)

    guard didWrite else {
      logger.error("failed to persist chunk \(chunkIndex) for \(parsed.fileId)")
      return
    }

    // The download may have been removed (declined/cancelled) during the write.
    guard
      let i = activeDownloads.firstIndex(where: { file in
        file.id == parsed.fileId && file.fromUser == peer
      })
    else {
      try? FileManager.default.removeItem(at: chunkURL)
      return
    }

    // Update download state.
    if activeDownloads[i].totalChunks == 0 {
      activeDownloads[i].totalChunks = Int(parsed.totalChunks)
    }
    activeDownloads[i].receivedChunkURLs[chunkIndex] = chunkURL
    activeDownloads[i].receivedSize += Int64(data.count)

    let received = activeDownloads[i].receivedSize
    let size = activeDownloads[i].fileSize
    activeDownloads[i].progress = size > 0 ? min(1.0, Double(received) / Double(size)) : 0

    // Completion check.
    let total = activeDownloads[i].totalChunks
    if total > 0, activeDownloads[i].receivedChunkURLs.count == total {
      let download = activeDownloads[i]

      logger.info("all \(total) chunks received for \(download.fileName) ← \(peer)")
      finalizeDownload(download, from: peer)
    }
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

  private func cleanupDownload(fileId: String, fromUser: String) {
    activeDownloads.removeAll { file in
      file.id == fileId && file.fromUser == fromUser
    }

    pendingChunkIndices[fileId] = nil
    let dir = chunkDirectory(for: fileId)
    try? FileManager.default.removeItem(at: dir)
  }

  /// Receiver rejected a pending offer. Stop the upload; they already know.
  private func handleFileDecline(fileId: String, from peer: String) {
    stopFileUpload(targetUser: peer, fileId: fileId, notifyRecipient: false)
  }

  /// Receiver cancelled an in-flight download. Stop sending; they already know.
  private func handleFileDownloadCancellation(fileId: String, from peer: String) {
    stopFileUpload(targetUser: peer, fileId: fileId, notifyRecipient: false)
  }

  private func handleFileUploadCancellation(fileId: String, from peer: String) {
    cleanupDownload(fileId: fileId, fromUser: peer)
    incomingFileOffers.removeAll { file in
      file.id == fileId && file.fromUser == peer
    }

    fileTransferCancelled.send(fileId)
    logger.info("upload cancelled by sender: \(fileId) ← \(peer)")
  }

  @discardableResult
  func stopFileUpload(targetUser: String, fileId: String, notifyRecipient: Bool = true) -> Bool {
    uploadTasks[fileId]?.cancel()
    uploadTasks[fileId] = nil

    guard
      let idx = activeUploads.firstIndex(where: { file in
        file.targetUser == targetUser && file.id == fileId
      })
    else {
      return false
    }
    let removed = activeUploads.remove(at: idx)

    let stillReferenced = activeUploads.contains { file in
      file.fileURL == removed.fileURL
    }
    if !stillReferenced {
      try? FileManager.default.removeItem(at: removed.fileURL)
    }

    if notifyRecipient {
      do {
        let data = try DataChannelMessage.encodeFileCancelUpload(FileCancelPayload(fileId: fileId))
        _ = signalingService.send(data, to: targetUser)
      } catch {
        logger.error("encodeFileCancelUpload failed: \(error)")
      }
    }

    logger.info("upload stopped: \(fileId) → \(targetUser) (notify=\(notifyRecipient))")
    return true
  }

  @discardableResult
  func cancelFileDownload(fromUser: String, fileId: String) -> Bool {
    guard
      activeDownloads.contains(where: { file in
        file.id == fileId && file.fromUser == fromUser
      })
    else {
      return false
    }

    cleanupDownload(fileId: fileId, fromUser: fromUser)
    fileTransferCancelled.send(fileId)

    let uploader = fromUser
    do {
      let data = try DataChannelMessage.encodeFileCancelDownload(FileCancelPayload(fileId: fileId))
      _ = signalingService.send(data, to: uploader)
    } catch {
      logger.error("encodeFileCancelDownload failed: \(error)")
    }

    logger.info("download cancelled: \(fileId) ← \(fromUser)")
    return true
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

    let uploader = fromUser
    guard signalingService.send(data, to: uploader) else {
      logger.warning("send failed for file-accept \(fileId) to \(uploader)")
      return false
    }

    var download = incomingFileOffers.remove(at: idx)
    download.isAccepted = true
    activeDownloads.append(download)

    logger.info("file-accept sent: \(fileId) → \(uploader)")
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

    let uploader = fromUser
    guard signalingService.send(data, to: uploader) else {
      logger.warning("send failed for file-decline \(fileId) to \(uploader)")
      return false
    }

    incomingFileOffers.remove(at: idx)
    logger.info("file-decline sent: \(fileId) → \(uploader)")
    return true
  }

  // MARK: Helpers

  /// Per-file scratch directory for incoming chunks: <tmp>/incoming/<fileId>/.
  private func chunkDirectory(for fileId: String) -> URL {
    // TODO: Change the path name from incoming to something better.
    FileManager.default.temporaryDirectory
      .appendingPathComponent("incoming", isDirectory: true)
      .appendingPathComponent(fileId, isDirectory: true)
  }

  private func finalizeDownload(_ download: FileDownload, from peer: String) {
    Task { @MainActor in
      let dir = chunkDirectory(for: download.id)
      let finalURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(download.id)-\(download.fileName)")

      // Assemble + (optional) verify off the main actor.
      let result: (ok: Bool, hashMismatch: Bool) = await Task.detached {
        do {
          // Concatenate chunks 0..<total in order.
          if FileManager.default.fileExists(atPath: finalURL.path) {
            try FileManager.default.removeItem(at: finalURL)
          }

          FileManager.default.createFile(atPath: finalURL.path, contents: nil)
          let out = try FileHandle(forWritingTo: finalURL)
          defer { try? out.close() }

          for index in 0..<download.totalChunks {
            let chunkURL = dir.appendingPathComponent("\(index)")
            let chunkData = try Data(contentsOf: chunkURL)
            try out.write(contentsOf: chunkData)
          }
          try? out.close()

          // Verify hash if the sender provided one.
          if let expectedHash = download.expectedHash {
            let actual = try BinaryChunk.sha256Hex(ofFileAt: finalURL)
            if actual != expectedHash {
              return (false, true)
            }
          }

          return (true, false)
        } catch {
          return (false, false)
        }
      }.value

      // Clean up scratch chunks regardless of outcome.
      try? FileManager.default.removeItem(at: dir)

      guard result.ok else {
        logger.error("finalize failed for \(download.fileName) (hashMismatch=\(result.hashMismatch))")

        // Remove the download + leave bubble in a non-completed state.
        activeDownloads.removeAll { $0.id == download.id && $0.fromUser == peer }
        try? FileManager.default.removeItem(at: finalURL)

        // TODO: surface failure to the user (toast / bubble status).
        return
      }

      if
        let i = activeDownloads.firstIndex(where: { file in
          file.id == download.id && file.fromUser == peer
        })
      {
        activeDownloads[i].fileURL = finalURL
      }

      sendFileReceived(fileId: download.id, to: peer)
      activeDownloads.removeAll { $0.id == download.id && $0.fromUser == peer }
      downloadCompleted.send((fileId: download.id, fileURL: finalURL))
      logger.info("download complete: \(download.fileName) ← \(peer)")
    }
  }

  private func sendFileReceived(fileId: String, to peer: String) {
    do {
      let data = try DataChannelMessage.encodeFileReceived(FileReceivedPayload(fileId: fileId))
      _ = signalingService.send(data, to: peer)
    } catch {
      logger.error("encodeFileReceived failed: \(error)")
    }
  }

  private func reconcilePeers(_ current: [String]) {
    let currentSet = Set(current)
    let departed = knownPeers.subtracting(current)

    knownPeers = currentSet
    for peer in departed {
      purgeTransfers(for: peer)
    }
  }

  private func purgeTransfers(for peer: String) {
    // Uploads to this peer — stop send loops, no notify (peer is gone).
    let uploadIds = activeUploads.filter { $0.targetUser == peer }.map(\.id)
    for fileId in uploadIds {
      stopFileUpload(targetUser: peer, fileId: fileId, notifyRecipient: false)
    }

    // Downloads from this peer — drop in-flight state + scratch, flip bubble.
    let downloadIds = activeDownloads.filter { $0.fromUser == peer }.map(\.id)
    for fileId in downloadIds {
      cleanupDownload(fileId: fileId, fromUser: peer)
      fileTransferCancelled.send(fileId)
    }

    // Pending offers never accepted.
    let offerIds = incomingFileOffers.filter { $0.fromUser == peer }.map(\.id)
    incomingFileOffers.removeAll { $0.fromUser == peer }
    for fileId in offerIds {
      fileTransferCancelled.send(fileId)
    }
  }
}
