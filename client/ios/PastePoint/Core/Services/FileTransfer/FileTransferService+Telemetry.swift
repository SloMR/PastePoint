//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation
import UniformTypeIdentifiers

// MARK: - Telemetry

extension FileTransferService {

  /// Wire values of the `file.transfer.receive` span outcome.
  enum ReceiveOutcome: String {
    case completed
    case crcFailed = "crc_failed"
    case noHash = "no_hash"
    case hashMismatch = "hash_mismatch"
    case missingChunks = "missing_chunks"
    case stalled
    case cancelled
  }

  /// Wire values of the `file.transfer.send` span outcome.
  enum SendOutcome: String {
    case queuedAllChunks = "queued_all_chunks"
    case abortedMaxErrors = "aborted_max_errors"
    case cancelled
  }

  /// Who cancelled a transfer (`cancelled_by` attribute).
  enum CancelledBy: String {
    case sender
    case receiver
    case peerLeft = "peer_left"
  }

  /// Opens the receive span once the first chunk reveals the chunk count.
  func startReceiveSpan(for download: FileDownload) {
    guard receiveSpans[download.id] == nil else { return }
    receiveSpans[download.id] = telemetry.startSpan(op: "file.transfer.receive", attributes: [
      "file_size_bytes": Int(download.fileSize),
      "mime": Self.mime(forFileName: download.fileName),
      "total_chunks": download.totalChunks,
    ])
  }

  /// Ends and forgets a download's span; safe to call more than once.
  func endReceiveSpan(fileId: String, outcome: ReceiveOutcome, attributes: Telemetry.Attributes = [:]) {
    guard let span = receiveSpans.removeValue(forKey: fileId) else { return }
    telemetry.endSpan(span, ok: outcome == .completed, outcome: outcome.rawValue, attributes: attributes)
  }

  /// Records how the chunk loop ended on the send span.
  nonisolated func markSendSpan(_ span: TelemetrySpan, _ outcome: SendOutcome, message: String? = nil) {
    telemetry.markSpan(span, ok: outcome == .queuedAllChunks, outcome: outcome.rawValue, message: message)
  }

  /// The models carry no MIME type, so derive it from the file extension.
  nonisolated static func mime(forFileName name: String) -> String {
    UTType(filenameExtension: (name as NSString).pathExtension)?.preferredMIMEType ?? "unknown"
  }

  /// Maps an assembly failure to its span outcome.
  nonisolated static func finalizeOutcome(_ reason: FileTransferFailureReason?) -> ReceiveOutcome {
    switch reason {
    case .integrity: .hashMismatch
    case .noHash: .noHash
    default: .missingChunks
    }
  }
}
