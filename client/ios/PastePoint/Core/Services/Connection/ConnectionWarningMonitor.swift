//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Combine
import Foundation
import Logging

@MainActor
final class ConnectionWarningMonitor: ObservableObject {
  @Published private(set) var showWarning: Bool = false

  private let peerDirectory: PeerDirectory
  private let signalingService: SignalingService
  private let logger = Logger(label: "ConnectionWarningMonitor")

  private static let warningDelay: TimeInterval = 15
  private var dismissed = false
  private var timers: [String: Task<Void, Never>] = [:]
  private var cancellables: Set<AnyCancellable> = []

  init(
    peerDirectory: PeerDirectory,
    signalingService: SignalingService,
  ) {
    self.peerDirectory = peerDirectory
    self.signalingService = signalingService

    peerDirectory.$peers
      .combineLatest(signalingService.$connectedPeers)
      .sink { [weak self] peers, connected in
        self?.reconcile(peers: peers, connected: connected)
      }
      .store(in: &cancellables)
  }

  func dismiss() {
    showWarning = false
    dismissed = true
  }

  // MARK: -

  private func reconcile(peers: [String], connected: Set<String>) {
    let expected = Set(peers)
    let unconnected = expected.subtracting(connected)

    for peer in Array(timers.keys) where !unconnected.contains(peer) {
      cancelTimer(for: peer)
    }

    for peer in unconnected where timers[peer] == nil {
      scheduleWarning(for: peer)
    }

    if unconnected.isEmpty {
      showWarning = false
      dismissed = false
    }
  }

  private func scheduleWarning(for peer: String) {
    guard !showWarning else { return }

    timers[peer] = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(Self.warningDelay * 1_000_000_000))

      guard !Task.isCancelled, let self else { return }

      self.timers[peer] = nil
      guard
        self.peerDirectory.peers.contains(peer),
        !self.signalingService.connectedPeers.contains(peer),
        !self.dismissed
      else {
        return
      }

      self.logger.warning("Peer \(peer) unconnected past \(Self.warningDelay)s — showing warning")
      self.showWarning = true
    }
  }

  private func cancelTimer(for peer: String) {
    timers[peer]?.cancel()
    timers[peer] = nil
  }
}
