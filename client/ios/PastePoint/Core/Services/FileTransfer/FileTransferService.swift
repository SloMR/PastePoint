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
  let outgoingAttachment = PassthroughSubject<ChatMessage, Never>()
  let downloadCompleted = PassthroughSubject<(fileId: String, fileURL: URL?), Never>()
  let outgoingGroupStatus = PassthroughSubject<OutgoingGroupStatus, Never>()
  let attachmentPreviewUpdated = PassthroughSubject<(fileId: String, previewDataUrl: String, previewMime: String?), Never>()
  let fileTransferCancelled = PassthroughSubject<String, Never>()
  let fileTransferFailed = PassthroughSubject<(fileId: String, reason: FileTransferFailureReason), Never>()

  private let downloadStallTimeout: TimeInterval = 30
  private var pendingChunkIndices: [String: Set<Int>] = [:]
  private var uploadTasks: [String: Task<Void, Never>] = [:]
  private var outgoingGroups: [String: UploadGroup] = [:]
  private var offerTasks: [String: Task<Void, Never>] = [:]
  private var stallWatchdog: Task<Void, Never>?
  private var knownPeers: Set<String> = []
  private var cancellables: Set<AnyCancellable> = []
  private var fileHashTasks: [URL: Task<String?, Never>] = [:]

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
  func prepareFileForSending(
    stagedFile: StagedFile,
    targetUser: String,
    groupId: String,
    hashTask: Task<String?, Never>? = nil,
    preview: PreviewGenerator.Preview? = nil,
  ) async -> Bool {
    guard stagedFile.size > 0 else {
      logger.warning("skipping empty file \(stagedFile.name)")
      return false
    }

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
        groupId: groupId,
        fileURL: stagedFile.url,
        kind: stagedFile.kind,
        displayName: stagedFile.name,
        fileSize: stagedFile.size,
        targetUser: targetUser,
        currentOffset: 0,
        progress: 0,
        phase: .sending,
      ),
    )
    logger.info("file-offer sent: \(stagedFile.name) (\(fileId)) → \(targetUser)")

    offerTasks[fileId] = Task { [weak self] in
      await self?.sendEnrichOffer(
        fileId: fileId,
        stagedFile: stagedFile,
        sender: sender,
        to: targetUser,
        hashTask: hashTask,
        preview: preview,
      )
      self?.offerTasks[fileId] = nil
    }
    return true
  }

  func sendStagedFile(_ stagedFile: StagedFile, to peers: [String]) async {
    guard stagedFile.size > 0 else {
      logger.warning("skipping empty file \(stagedFile.name)")
      return
    }

    await userService.waitForUsername()
    let sender = userService.user
    let groupId = UUID().uuidString
    outgoingGroups[groupId] = UploadGroup(total: peers.count)
    let preview = await PreviewGenerator.make(forFileAt: stagedFile.url)

    outgoingAttachment.send(
      ChatMessage(
        from: sender,
        text: stagedFile.name,
        type: .attachment,
        fileTransfer: FileTransferData(
          fileId: UUID().uuidString,
          fileName: stagedFile.name,
          fileSize: stagedFile.size,
          fromUser: sender,
          status: .pending,
          previewDataUrl: preview?.dataUrl,
          previewMime: preview?.mime,
          groupId: groupId,
          deliveredCount: 0,
          recipientCount: peers.count,
        ),
        isMine: true,
      ),
    )

    let hashTask = prewarmFileHash(forFileAt: stagedFile.url)
    for peer in peers {
      await prepareFileForSending(
        stagedFile: stagedFile,
        targetUser: peer,
        groupId: groupId,
        hashTask: hashTask,
        preview: preview,
      )
    }
    // All peers have consumed the shared hash; drop the cache entry.
    fileHashTasks[stagedFile.url] = nil
  }

  /// Pre-computes a file's BLAKE3 hash so it's ready by send time.
  @discardableResult
  func prewarmFileHash(forFileAt url: URL) -> Task<String?, Never> {
    if let existing = fileHashTasks[url] { return existing }
    let task = Task.detached { try? BinaryChunk.blake3Hex(ofFileAt: url) }
    fileHashTasks[url] = task
    return task
  }

  func sendFiles(_ files: [StagedFile], to member: String) async {
    for file in files {
      await sendStagedFile(file, to: [member])
    }
  }

  @discardableResult
  func stopFileUpload(targetUser: String, fileId: String, notifyRecipient: Bool = true) -> Bool {
    uploadTasks[fileId]?.cancel()
    uploadTasks[fileId] = nil
    offerTasks[fileId]?.cancel()
    offerTasks[fileId] = nil

    guard
      let idx = activeUploads.firstIndex(where: { file in
        file.targetUser == targetUser && file.id == fileId
      })
    else {
      return false
    }
    let removed = activeUploads.remove(at: idx)
    markGroupOutcome(removed.groupId, success: false)
    releaseSourceFile(of: removed)

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
    download.lastActivityAt = Date()
    activeDownloads.append(download)
    startStallWatchdog()

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

  // MARK: - Peer Lifecycle

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

  func cancelAllTransfers() {
    let peers = Set(activeUploads.map(\.targetUser))
      .union(activeDownloads.map(\.fromUser))
      .union(incomingFileOffers.map(\.fromUser))
    for peer in peers {
      purgeTransfers(for: peer)
    }
  }
}

// MARK: - Sending

extension FileTransferService {
  func handleFileAccept(payload: FileAcceptPayload, from peer: String) {
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

    let offerTask = offerTasks[payload.fileId]
    let task = Task.detached { [weak self] in
      guard let self else { return }
      await offerTask?.value
      await self.runChunkSendLoop(uploadId: upload.id, targetUser: peer)
    }
    uploadTasks[upload.id] = task
  }

  nonisolated func runChunkSendLoop(uploadId: String, targetUser: String) async {
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

    let progressFlushInterval: TimeInterval = 0.25
    var lastProgressFlush = Date.distantPast

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
      guard await sendEncodedChunk(encoded, to: targetUser) else {
        logger.info("chunk loop cancelled (back-pressure wait) for \(uploadId)")
        return
      }

      bytesSent += Int64(chunkData.count)
      chunkIndex += 1

      let now = Date()
      if now.timeIntervalSince(lastProgressFlush) >= progressFlushInterval {
        lastProgressFlush = now
        await applyUploadProgress(uploadId: uploadId, bytesSent: bytesSent, fileSize: snapshot.fileSize)
      }
    }

    // 4. Final flush + flip phase to .finalizing — bytes shipped, awaiting
    //    receiver ack. The flush guarantees the bar hits 100% even if the last
    //    periodic update was throttled out.
    await applyUploadProgress(
      uploadId: uploadId,
      bytesSent: bytesSent,
      fileSize: snapshot.fileSize,
      phase: .finalizing,
    )
    logger.info("chunk loop: finished \(chunkIndex) chunks for \(uploadId) → \(targetUser)")
  }

  /// Applies progress (and optionally a phase) to the matching active upload.
  private func applyUploadProgress(
    uploadId: String,
    bytesSent: Int64,
    fileSize: Int64,
    phase: FileUpload.Phase? = nil,
  ) {
    guard let idx = activeUploads.firstIndex(where: { $0.id == uploadId }) else { return }
    activeUploads[idx].currentOffset = bytesSent
    activeUploads[idx].progress = min(1.0, Double(bytesSent) / Double(fileSize))
    if let phase { activeUploads[idx].phase = phase }
  }

  /// Sends one encoded chunk, waiting out back-pressure. False if cancelled.
  private nonisolated func sendEncodedChunk(_ encoded: Data, to targetUser: String) async -> Bool {
    while true {
      let sent = await MainActor.run {
        signalingService.send(encoded, to: targetUser, isBinary: true)
      }
      if sent { return true }
      try? await Task.sleep(nanoseconds: 50_000_000) // 50 ms
      if Task.isCancelled { return false }
    }
  }

  private func sendEnrichOffer(
    fileId: String,
    stagedFile: StagedFile,
    sender: String,
    to targetUser: String,
    hashTask: Task<String?, Never>? = nil,
    preview: PreviewGenerator.Preview? = nil,
  ) async {
    let hash: String?
    if let hashTask {
      hash = await hashTask.value
    } else {
      hash = await Task.detached {
        try? BinaryChunk.blake3Hex(ofFileAt: stagedFile.url)
      }.value
    }

    guard let hash else {
      logger.error("hash failed for \(fileId); aborting send")
      stopFileUpload(targetUser: targetUser, fileId: fileId) // removes upload + sends file-cancel-upload
      fileTransferFailed.send((fileId: fileId, reason: .sendHashFailed))
      return
    }

    let resolvedPreview: PreviewGenerator.Preview?
    if let preview {
      resolvedPreview = preview
    } else {
      resolvedPreview = await PreviewGenerator.make(forFileAt: stagedFile.url)
    }

    let enriched = FileOfferPayload(
      fileId: fileId,
      fileName: stagedFile.name,
      fileSize: stagedFile.size,
      fromUser: sender,
      fileHash: hash,
      previewDataUrl: resolvedPreview?.dataUrl,
      previewMime: resolvedPreview?.mime,
    )

    do {
      _ = signalingService.send(try DataChannelMessage.encodeFileOffer(enriched), to: targetUser)
      logger.info("enriched file-offer sent: \(fileId) → \(targetUser)")
    } catch {
      logger.error("encodeFileOffer (enriched) failed for \(fileId): \(error)")
    }
  }
}

// MARK: - Inbound Handling

extension FileTransferService {
  func handleFileEvent(_ event: FileChannelEvent) {
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
    if let i = incomingFileOffers.firstIndex(where: { $0.id == payload.fileId }) {
      if let hash = payload.fileHash, incomingFileOffers[i].expectedHash == nil {
        incomingFileOffers[i].expectedHash = hash
        logger.info("merged hash into pending offer \(payload.fileId)")
      }

      if
        let preview = payload.previewDataUrl,
        let previewMime = payload.previewMime,
        incomingFileOffers[i].previewDataUrl == nil
      {
        incomingFileOffers[i].previewDataUrl = preview
        incomingFileOffers[i].previewMime = previewMime

        attachmentPreviewUpdated.send((fileId: payload.fileId, previewDataUrl: preview, previewMime: previewMime))
        logger.info("merged preview into pending offer \(payload.fileId)")
      }
      return
    }

    if let i = activeDownloads.firstIndex(where: { $0.id == payload.fileId && $0.fromUser == peer }) {
      if let hash = payload.fileHash, activeDownloads[i].expectedHash == nil {
        activeDownloads[i].expectedHash = hash
        logger.info("merged hash into accepted download \(payload.fileId)")
      }

      if
        let preview = payload.previewDataUrl,
        let previewMime = payload.previewMime,
        activeDownloads[i].previewDataUrl == nil
      {
        activeDownloads[i].previewDataUrl = preview
        activeDownloads[i].previewMime = previewMime

        attachmentPreviewUpdated.send((fileId: payload.fileId, previewDataUrl: preview, previewMime: previewMime))
        logger.info("merged preview into accepted download \(payload.fileId)")
      }
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
      lastActivityAt: Date(),
      progress: 0,
      isAccepted: false,
      expectedHash: payload.fileHash,
      previewDataUrl: payload.previewDataUrl,
      previewMime: payload.previewMime,
    )
    incomingFileOffers.append(download)

    let fileTransfer = FileTransferData(
      fileId: payload.fileId,
      fileName: payload.fileName,
      fileSize: payload.fileSize,
      fromUser: peer,
      status: .pending,
      previewDataUrl: payload.previewDataUrl,
      previewMime: payload.previewMime,
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

  func handleChunk(_ parsed: ParsedChunk, from peer: String) async {
    guard
      let idx = activeDownloads.firstIndex(where: { file in
        file.id == parsed.fileId && file.fromUser == peer
      })
    else {
      // No accepted download for this chunk — offer not accepted, or already done.
      return
    }

    guard parsed.isValid else {
      logger.warning("invalid chunk \(parsed.chunkIndex) for \(parsed.fileId), failing transfer")
      failDownload(fileId: parsed.fileId, from: peer, reason: .integrity)
      return
    }

    if activeDownloads[idx].expectedHash == nil {
      logger.warning("no hash for \(parsed.fileId); rejecting early")
      failDownload(fileId: parsed.fileId, from: peer, reason: .noHash)
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
    activeDownloads[i].lastActivityAt = Date()

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

  private func finalizeDownload(_ download: FileDownload, from peer: String) {
    Task { @MainActor in
      let dir = chunkDirectory(for: download.id)

      let completedDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("completed/\(download.id)", isDirectory: true)
      try? FileManager.default.createDirectory(at: completedDir, withIntermediateDirectories: true)
      let finalURL = completedDir.appendingPathComponent(download.fileName)

      let logger = self.logger
      // Assemble + (optional) verify off the main actor.
      let result: (ok: Bool, reason: FileTransferFailureReason?) = await Task.detached {
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

          // Verify hash.
          guard let expectedHash = download.expectedHash else {
            return (false, .noHash)
          }
          let actual = try BinaryChunk.blake3Hex(ofFileAt: finalURL)
          if actual != expectedHash {
            return (false, .integrity)
          }

          logger.info("file integrity verified \(download.fileName) ✓")
          return (true, nil)
        } catch {
          return (false, .assembly)
        }
      }.value

      // Clean up scratch chunks regardless of outcome.
      try? FileManager.default.removeItem(at: dir)

      guard result.ok else {
        logger.error("finalize failed for \(download.fileName), reason: \(result.reason ?? .assembly)")

        try? FileManager.default.removeItem(at: completedDir)
        failDownload(fileId: download.id, from: peer, reason: result.reason ?? .assembly)
        return
      }

      sendFileReceived(fileId: download.id, to: peer)
      activeDownloads.removeAll { $0.id == download.id && $0.fromUser == peer }
      stopStallWatchdogIfIdle()

      let outcome = await ReceivedFileSaver.save(at: finalURL, fileName: download.fileName)
      try? FileManager.default.removeItem(at: completedDir)

      switch outcome {
      case .photos:
        downloadCompleted.send((fileId: download.id, fileURL: nil))
      case let .documents(dest):
        downloadCompleted.send((fileId: download.id, fileURL: dest))
      case .permissionDenied:
        fileTransferFailed.send((fileId: download.id, reason: .photosPermissionDenied))
        return
      case .failed:
        fileTransferFailed.send((fileId: download.id, reason: .saveFailed))
        return
      }
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
    markGroupOutcome(removed.groupId, success: true)
    logger.info("file-received ack: \(payload.fileId) ← \(peer)")

    // Delete the tmp file only if no other in-flight upload references it.
    // Multiple peer-specific FileUploads share the same source `fileURL` when the
    // user sent one file to many peers; the last one out deletes.
    releaseSourceFile(of: removed)
  }

  // MARK: Cancellation

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

  func cleanupDownload(fileId: String, fromUser: String) {
    activeDownloads.removeAll { file in
      file.id == fileId && file.fromUser == fromUser
    }

    stopStallWatchdogIfIdle()
    pendingChunkIndices[fileId] = nil
    let dir = chunkDirectory(for: fileId)
    try? FileManager.default.removeItem(at: dir)
  }

  private func releaseSourceFile(of upload: FileUpload) {
    let stillReferenced = activeUploads.contains { file in
      file.fileURL == upload.fileURL
    }
    guard !stillReferenced else { return }

    upload.kind.releaseSource(at: upload.fileURL)
    logger.info("released source (\(upload.kind)): \(upload.fileURL.lastPathComponent)")
  }

  private func failDownload(fileId: String, from peer: String, reason: FileTransferFailureReason) {
    cleanupDownload(fileId: fileId, fromUser: peer)

    do {
      let data = try DataChannelMessage.encodeFileCancelDownload(FileCancelPayload(fileId: fileId))
      _ = signalingService.send(data, to: peer)
    } catch {
      logger.error("encodeFileCancelDownload (fail) failed: \(error)")
    }

    fileTransferFailed.send((
      fileId: fileId,
      reason: reason,
    ))
  }

  // MARK: Stall Watchdog

  private func startStallWatchdog() {
    guard stallWatchdog == nil else { return }
    stallWatchdog = Task { [weak self] in
      while true {
        try? await Task.sleep(nanoseconds: 5_000_000_000) // TODO: change this as const
        if Task.isCancelled { return }

        guard let self else { return }
        self.sweepStalledDownloads()
      }
    }
  }

  private func stopStallWatchdogIfIdle() {
    guard activeDownloads.isEmpty else { return }
    stallWatchdog?.cancel()
    stallWatchdog = nil
  }

  private func sweepStalledDownloads() {
    let now = Date()
    let stalled = activeDownloads.filter {
      now.timeIntervalSince($0.lastActivityAt) > downloadStallTimeout
    }
    for download in stalled {
      logger.warning("download \(download.id) stalled (\(downloadStallTimeout)s no chunk) — failing")
      failDownload(fileId: download.id, from: download.fromUser, reason: .stalled)
    }
  }

  // MARK: Helpers

  /// Per-file scratch directory for incoming chunks: <tmp>/incoming/<fileId>/.
  private func chunkDirectory(for fileId: String) -> URL {
    // TODO: Change the path name from incoming to something better.
    FileManager.default.temporaryDirectory
      .appendingPathComponent("incoming", isDirectory: true)
      .appendingPathComponent(fileId, isDirectory: true)
  }
}

// MARK: - Outgoing Group Aggregation

extension FileTransferService {
  struct OutgoingGroupStatus: Sendable {
    let groupId: String
    let status: FileTransferStatus
    let delivered: Int
    let total: Int
  }

  private struct UploadGroup {
    let total: Int
    var completed = 0
    var failed = 0
  }

  private func markGroupOutcome(_ groupId: String, success: Bool) {
    guard outgoingGroups[groupId] != nil else { return }
    if success {
      outgoingGroups[groupId]?.completed += 1
    } else {
      outgoingGroups[groupId]?.failed += 1
    }

    recomputeGroup(groupId)
  }

  private func recomputeGroup(_ groupId: String) {
    guard let group = outgoingGroups[groupId] else { return }
    let resolved = group.completed + group.failed >= group.total
    let status: FileTransferStatus =
      group.completed > 0 ? .completed // Sent
      : resolved ? .failed // Not delivered
      : .pending

    outgoingGroupStatus.send(OutgoingGroupStatus(groupId: groupId, status: status, delivered: group.completed, total: group.total))
    if resolved {
      outgoingGroups[groupId] = nil
    }
  }
}
