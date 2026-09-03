//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Combine
import Foundation

// MARK: - Outgoing Group Aggregation

extension FileTransferService {
  /// Aggregate delivery state of one attachment sent to several peers, for the sender bubble.
  struct OutgoingGroupStatus: Sendable {
    let groupId: String
    let status: FileTransferStatus
    let delivered: Int
    let total: Int
  }

  /// Per-peer tally for one fanned-out attachment.
  struct UploadGroup {
    let total: Int
    var completed = 0
    var failed = 0
  }

  /// Counts one peer's delivery result and republishes the group's status.
  func markGroupOutcome(_ groupId: String, success: Bool) {
    guard outgoingGroups[groupId] != nil else { return }
    if success {
      outgoingGroups[groupId]?.completed += 1
    } else {
      outgoingGroups[groupId]?.failed += 1
    }

    recomputeGroup(groupId)
  }

  /// Derives Sent / Not delivered / pending from the tally; forgets the group once every peer settled.
  func recomputeGroup(_ groupId: String) {
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
