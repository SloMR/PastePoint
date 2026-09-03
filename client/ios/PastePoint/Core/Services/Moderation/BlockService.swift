//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Combine
import Foundation

@MainActor
final class BlockService: ObservableObject {

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

    log.info("blocking peer")
    blockedPeers.insert(peer)
  }

  func unblock(_ peer: String) {
    log.info("unblocking peer")
    blockedPeers.remove(peer)
  }

  func isBlocked(_ peer: String) -> Bool {
    blockedPeers.contains(peer)
  }

  private func clear() {
    guard !blockedPeers.isEmpty else { return }

    log.debug("clearing blocks — identities are reassigned on reconnect")
    blockedPeers.removeAll()
  }
}
