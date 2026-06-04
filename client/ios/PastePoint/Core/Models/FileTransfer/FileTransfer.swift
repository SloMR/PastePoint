//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation

// MARK: Payloads

struct FileOfferPayload: Codable, Sendable {
  let fileId: String
  let fileName: String
  let fileSize: Int64
  let fromUser: String
  let fileHash: String?
  let previewDataUrl: String?
  let previewMime: String?
}

struct FileAcceptPayload: Codable, Sendable {
  let fileId: String
}

struct FileDeclinePayload: Codable, Sendable {
  let fileId: String
}

struct FileCancelPayload: Codable, Sendable {
  let fileId: String
}

struct FileReceivedPayload: Codable, Sendable {
  let fileId: String
}

// MARK: Status

enum FileTransferStatus: String, Codable, Sendable {
  case pending
  case accepted
  case declined
  case completed
  case cancelled
  case failed
}

enum FileTransferFailureReason: Sendable {
  case integrity // SHA-256 / CRC mismatch
  case assembly // couldn't read/write chunks to disk
  case noHash // receiver: sender sent no hash -> reject (verify is mandatory)
  case sendHashFailed // sender: couldn't hash the file -> send aborted
}

// MARK: Attachment Bubble Data

struct FileTransferData: Codable, Sendable, Equatable {
  let fileId: String
  let fileName: String
  let fileSize: Int64
  let fromUser: String
  var status: FileTransferStatus
  var fileURL: URL?
}

// MARK: Local State

struct FileUpload: Identifiable, Sendable {
  enum Phase: Sendable {
    case sending
    case finalizing
  }

  let id: String
  let fileURL: URL
  let displayName: String
  let fileSize: Int64
  let targetUser: String
  var currentOffset: Int64
  var progress: Double
  var phase: Phase
}

struct FileDownload: Identifiable, Sendable {
  let id: String
  let fileName: String
  let fileSize: Int64
  let fromUser: String
  var totalChunks: Int
  var receivedSize: Int64
  var receivedChunkURLs: [Int: URL]
  var progress: Double
  var isAccepted: Bool
  var expectedHash: String?
  var fileURL: URL?
  // TODO: file-transfer preview — add `previewDataUrl: String?` and `previewMime: String?`
  //       and generate a JPEG thumbnail (≤150KB) at send time to match web's
}

// MARK: Staging

/// A file the user has picked but not yet sent. Lives in the input bar until
/// they hit send (→ becomes a `FileUpload`) or remove it.
struct StagedFile: Identifiable, Sendable, Equatable {
  let id: UUID
  let name: String
  let size: Int64
  let url: URL
}
