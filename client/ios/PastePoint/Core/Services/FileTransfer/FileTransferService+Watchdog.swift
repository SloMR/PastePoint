//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation

// MARK: - Stall Watchdog

extension FileTransferService {
  private static let stallSweepInterval: Duration = .seconds(5)

  func startStallWatchdog() {
    guard stallWatchdog == nil else { return }
    stallWatchdog = Task { [weak self] in
      while true {
        try? await Task.sleep(for: Self.stallSweepInterval)
        if Task.isCancelled { return }

        guard let self else { return }
        self.sweepStalledDownloads()
      }
    }
  }

  func stopStallWatchdogIfIdle() {
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
      log.warning("download \(download.id) stalled (\(downloadStallTimeout)s no chunk) — failing")
      failDownload(fileId: download.id, from: download.fromUser, reason: .stalled, outcome: .stalled, attributes: [
        "bytes_received": Int(download.receivedSize),
      ])
    }
  }
}
