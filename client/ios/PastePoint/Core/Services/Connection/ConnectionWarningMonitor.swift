//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Combine
import Foundation

@MainActor
final class ConnectionWarningMonitor: ObservableObject {
  @Published private(set) var showWarning: Bool = false

  private let peerDirectory: PeerDirectory
  private let signalingService: SignalingService

  private static let warningDelay: TimeInterval = 25
  private var dismissed = false
  private var timer: Task<Void, Never>?
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

  private func isIsolated(peers: [String], connected: Set<String>) -> Bool {
    !peers.isEmpty && connected.isEmpty
  }

  private func reconcile(peers: [String], connected: Set<String>) {
    guard isIsolated(peers: peers, connected: connected) else {
      timer?.cancel()
      timer = nil
      showWarning = false
      dismissed = false
      return
    }

    guard timer == nil, !showWarning else { return }
    scheduleWarning()
  }

  private func scheduleWarning() {
    timer = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(Self.warningDelay * 1_000_000_000))

      guard !Task.isCancelled, let self else { return }
      self.timer = nil

      guard
        self.isIsolated(
          peers: self.peerDirectory.peers,
          connected: self.signalingService.connectedPeers,
        ),
        !self.dismissed
      else {
        return
      }

      log.warning("No peer reachable past \(Self.warningDelay)s — showing warning")
      self.showWarning = true
    }
  }
}
