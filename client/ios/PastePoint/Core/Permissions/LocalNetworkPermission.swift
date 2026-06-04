//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation
import Logging
import Network
import os

enum LocalNetworkPermission {
  private static let logger = Logger(label: "LocalNetworkPermission")

  static func isDenied() async -> Bool {
    logger.info("Checking local network permission")

    let port = NWEndpoint.Port(integerLiteral: UInt16(AppEnvironment.wsPort ?? 443))
    let connection = NWConnection(host: NWEndpoint.Host(AppEnvironment.host), port: port, using: .tcp)
    let resolved = OSAllocatedUnfairLock(initialState: false)

    let claim: @Sendable () -> Bool = {
      resolved.withLock { state in
        guard !state else { return false }
        state = true
        return true
      }
    }

    return await withCheckedContinuation { continuation in
      connection.stateUpdateHandler = { newState in
        Task { @MainActor in
          switch newState {
          case .ready:
            guard claim() else { return }
            Self.logger.info("Connection ready — permission granted")
            connection.cancel()
            continuation.resume(returning: false)
          case .waiting(let error):
            guard claim() else { return }
            Self.logger.warning("Connection waiting — \(error.localizedDescription) — assuming denied")
            connection.cancel()
            continuation.resume(returning: true)
          case .failed(let error):
            guard claim() else { return }
            Self.logger.error("Connection failed — \(error.localizedDescription)")
            connection.cancel()
            continuation.resume(returning: false)
          default:
            break
          }
        }
      }

      connection.start(queue: .main)

      Task {
        try? await Task.sleep(for: .seconds(3))
        guard claim() else { return }
        Self.logger.info("Timeout — assuming permitted")
        connection.cancel()
        continuation.resume(returning: false)
      }
    }
  }
}
