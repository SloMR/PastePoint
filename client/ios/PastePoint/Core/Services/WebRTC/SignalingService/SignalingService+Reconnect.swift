//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation
import WebRTC

// MARK: - Reconnect

extension SignalingService {

  func scheduleReconnect(to peer: String) {
    guard reconnectTasks[peer] == nil else {
      log.debug("already scheduled for \(peer)")
      return
    }

    // Only connect if the peer is still expected to be in the room
    guard peerDirectory.peers.contains(peer) else {
      log.info("no longer a peer, skipping reconnect")
      finishConnectSpan(peer, ok: false, outcome: .cancelled)
      reconnectAttempts[peer] = nil
      connectingPeers.remove(peer)
      discardPending(for: peer)
      return
    }

    let attempts = reconnectAttempts[peer] ?? 0
    guard attempts < Self.maxReconnectAttempts else {
      log.error("max reconnect attempts reached")
      finishConnectSpanAsFailed(peer, reason: .maxReconnectsExceeded)
      reconnectAttempts[peer] = nil
      connectingPeers.remove(peer)
      discardPending(for: peer)
      return
    }

    reconnectAttempts[peer] = attempts + 1
    connectingPeers.insert(peer)

    // Exponential backoff: 2s, 3s, 4.5s, ...
    let delay = min(Self.baseReconnectDelay * pow(1.5, Double(attempts)), Self.maxReconnectDelay)
    log.warning("reconnect attempt \(attempts + 1) in \(delay)s")

    reconnectTasks[peer] = Task { [weak self, clock] in
      try? await clock.sleep(for: .seconds(delay))
      if Task.isCancelled { return }
      guard let self else { return }
      self.reconnectTasks[peer] = nil

      guard self.peerDirectory.peers.contains(peer) else {
        log.info("peer left during backoff, skipping")
        self.finishConnectSpan(peer, ok: false, outcome: .cancelled)
        self.reconnectAttempts[peer] = nil
        connectingPeers.remove(peer)
        self.discardPending(for: peer)
        return
      }

      // Don't reconnect if we have already healed since scheduling
      if self.connectedPeers.contains(peer) {
        log.debug("\(peer) already healthy, skipping")
        self.reconnectAttempts[peer] = nil
        connectingPeers.remove(peer)
        return
      }

      log.info("reconnecting to peer")
      self.closePeerConnection(peer, resetReconnectState: false)
      await self.initiateConnection(to: peer)
    }

  }

  func startConnectionTimeout(for peer: String) {
    connectionRequestTimeouts[peer]?.cancel()
    connectionRequestTimeouts[peer] = nil
    connectionTimeouts[peer]?.cancel()
    connectionTimeouts[peer] = Task { [weak self, clock] in
      try? await clock.sleep(for: .seconds(Self.connectionTimeout))

      if let pc = self?.peerConnections[peer], [.checking, .connected, .completed].contains(await WebRTCQueue.states(of: pc).ice) {
        try? await clock.sleep(for: .seconds(Self.connectionCeiling - Self.connectionTimeout))
      }

      guard let self else { return }
      if Task.isCancelled { return }
      self.connectionTimeouts[peer] = nil

      // Check if we already connected then don't do anything
      if self.connectedPeers.contains(peer) { return }

      log.warning("connectionTimeout: peer did not connect in time, treating as failure")
      self.logConnectionDiagnostics(for: peer)
      self.scheduleReconnect(to: peer)
    }
  }

  func clearConnectionTimeout(for peer: String) {
    connectionTimeouts[peer]?.cancel()
    connectionTimeouts[peer] = nil
  }

  /// Drops a retry scheduled for an earlier attempt, so it can't tear down the one starting now.
  func cancelScheduledReconnect(for peer: String) {
    reconnectTasks[peer]?.cancel()
    reconnectTasks[peer] = nil
  }

  /// Watchdog for the non-caller: if the designated caller never re-offers within
  /// `connectionRequestTimeout`, force-initiate ourselves.
  /// Superseded by `startConnectionTimeout` once a real
  /// peer connection attempt begins; cleared in `closePeerConnection`.
  func startConnectionRequestTimeout(for peer: String) {
    connectionRequestTimeouts[peer]?.cancel()
    connectionRequestTimeouts[peer] = Task { [weak self, clock] in
      try? await clock.sleep(for: .seconds(Self.connectionRequestTimeout))

      guard !Task.isCancelled, let self else { return }
      self.connectionRequestTimeouts[peer] = nil

      guard self.peerConnections[peer] == nil, self.peerDirectory.peers.contains(peer) else {
        if !self.peerDirectory.peers.contains(peer) {
          self.finishConnectSpan(peer, ok: false, outcome: .cancelled)
        }
        return
      }
      log.warning("no offer within \(Self.connectionRequestTimeout)s — force-initiating")
      await self.initiateConnection(to: peer, force: true)
    }
  }

  func closePeerConnection(_ peer: String, resetReconnectState: Bool = true) {
    clearConnectionTimeout(for: peer)
    connectionRequestTimeouts[peer]?.cancel()
    connectionRequestTimeouts[peer] = nil
    if resetReconnectState {
      reconnectTasks[peer]?.cancel()
      reconnectTasks[peer] = nil
      reconnectAttempts[peer] = nil
      pendingMessages[peer] = nil
    }

    let dataChannel = dataChannels.removeValue(forKey: peer)
    let peerConnection = peerConnections.removeValue(forKey: peer)
    if let peerConnection {
      describedConnections.remove(ObjectIdentifier(peerConnection))
    }
    WebRTCQueue.close(peerConnection, channel: dataChannel)

    candidateQueues[peer] = nil
    collectedCandidates[peer] = nil
    connectionLocks.remove(peer)
    connectedPeers.remove(peer)
    if resetReconnectState {
      connectingPeers.remove(peer)
    }
  }

}
