//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Combine
import Foundation

// MARK: - Upload Batch Aggregation

extension FileTransferService {
  /// Aggregate delivery state of one attachment sent to several peers, for the sender bubble.
  struct UploadBatchStatus: Sendable {
    let batchId: String
    let status: FileTransferStatus
    let delivered: Int
    let total: Int
  }

  /// Per-peer tally for one fanned-out attachment.
  struct UploadBatch {
    let total: Int
    var completed = 0
    var failed = 0
  }

  /// Counts one peer's delivery result and republishes the batch's status.
  func markBatchOutcome(_ batchId: String, success: Bool) {
    guard uploadBatches[batchId] != nil else { return }
    if success {
      uploadBatches[batchId]?.completed += 1
    } else {
      uploadBatches[batchId]?.failed += 1
    }

    recomputeBatch(batchId)
  }

  /// Derives Sent / Not delivered / pending from the tally; forgets the batch once every peer settled.
  func recomputeBatch(_ batchId: String) {
    guard let batch = uploadBatches[batchId] else { return }
    let resolved = batch.completed + batch.failed >= batch.total
    let status: FileTransferStatus =
      batch.completed > 0 ? .completed // Sent
      : resolved ? .failed // Not delivered
      : .pending

    uploadBatchStatus.send(UploadBatchStatus(batchId: batchId, status: status, delivered: batch.completed, total: batch.total))
    if resolved {
      uploadBatches[batchId] = nil
    }
  }
}
