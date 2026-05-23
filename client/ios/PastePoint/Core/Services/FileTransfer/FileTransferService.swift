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

  init(signalingService: SignalingService, userService: UserService) {
    self.signalingService = signalingService
    self.userService = userService
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
}
