//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Combine
import Foundation
import Logging

@MainActor
final class BlockService: ObservableObject {
  private let logger = Logger(label: "Block")

  @Published private(set) var blockedPeers: Set<String> = []

  private var cancellables = Set<AnyCancellable>()

  init(wsService: WebSocketConnectionService) {
    wsService.$isConnected
      .receive(on: DispatchQueue.main)
      .sink { [weak self] connected in
        if !connected { self?.clear() }
      }
      .store(in: &cancellables)
  }

  func block(_ peer: String) {
    guard !peer.isEmpty else { return }

    logger.info("blocking peer \(peer)")
    blockedPeers.insert(peer)
  }

  func unblock(_ peer: String) {
    logger.info("unblocking peer \(peer)")
    blockedPeers.remove(peer)
  }

  func isBlocked(_ peer: String) -> Bool {
    blockedPeers.contains(peer)
  }

  private func clear() {
    guard !blockedPeers.isEmpty else { return }

    logger.debug("clearing blocks — identities are reassigned on reconnect")
    blockedPeers.removeAll()
  }
}
