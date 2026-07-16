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

  @MainActor
  static func requestAccess() {
    logger.info("Requesting local network permission")
    let browser = NWBrowser(for: .bonjour(type: "_pastepoint._tcp", domain: nil), using: NWParameters())
    browser.stateUpdateHandler = { _ in }
    browser.start(queue: .main)

    Task { @MainActor in
      try? await Task.sleep(for: .seconds(2))
      browser.cancel()
    }
  }

  static func isDenied() async -> Bool {
    logger.info("Checking local network permission")

    let port = NWEndpoint.Port(integerLiteral: UInt16(AppEnvironment.localNetworkProbePort))
    let connection = NWConnection(host: NWEndpoint.Host(AppEnvironment.localNetworkProbeHost), port: port, using: .tcp)
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
            if case .posix(.ECONNREFUSED) = error {
              Self.logger.info("Connection refused — server down, permission granted")
              connection.cancel()
              continuation.resume(returning: false)
            } else {
              Self.logger.warning("Connection waiting — \(error.localizedDescription) — assuming denied")
              connection.cancel()
              continuation.resume(returning: true)
            }
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
