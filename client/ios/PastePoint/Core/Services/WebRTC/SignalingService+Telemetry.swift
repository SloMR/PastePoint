//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation
import WebRTC

// MARK: - Diagnostics

extension SignalingService {

  /// Extracts the ICE candidate type (`host` / `srflx` / `relay` / `prflx`) from
  /// a candidate SDP line, which carries a `typ <type>` token.
  func candidateType(from sdp: String) -> String {
    let parts = sdp.split(separator: " ")
    if let i = parts.firstIndex(of: "typ"), i + 1 < parts.count {
      return String(parts[i + 1])
    }
    return "unknown"
  }

  /// Logs why a peer connection failed, with the candidate mix that was gathered.
  func logConnectionDiagnostics(for peer: String) {
    guard let pc = peerConnections[peer] else { return }
    let candidates = collectedCandidates[peer] ?? []
    let hasRelay = candidates.contains("relay")
    let hasSrflx = candidates.contains("srflx")

    var report = "Connection FAILED:\n"
    report += "  State: \(pc.connectionState.rawValue) / ICE: \(pc.iceConnectionState.rawValue)\n"
    report += "  Candidates: \(candidates.count) total (relay: \(hasRelay ? "✓" : "✗"), srflx: \(hasSrflx ? "✓" : "✗"))"
    if !hasRelay {
      report += "\n  ISSUE: No TURN relay candidates — connection will fail behind symmetric NAT"
    }
    log.error("\(report)")
  }

  /// Gathered ICE candidates per type, e.g. `["host": 2, "relay": 1]`.
  func candidateTypeCounts(for peer: String) -> [String: Int] {
    Dictionary((collectedCandidates[peer] ?? []).map { ($0, 1) }, uniquingKeysWith: +)
  }

  /// Stable wire name for a peer-connection state.
  nonisolated static func name(_ state: RTCPeerConnectionState) -> String {
    switch state {
    case .new: return "new"
    case .connecting: return "connecting"
    case .connected: return "connected"
    case .disconnected: return "disconnected"
    case .failed: return "failed"
    case .closed: return "closed"
    @unknown default: return "unknown"
    }
  }

  /// Stable wire name for an ICE-connection state.
  nonisolated static func name(_ state: RTCIceConnectionState) -> String {
    switch state {
    case .new: return "new"
    case .checking: return "checking"
    case .connected: return "connected"
    case .completed: return "completed"
    case .failed: return "failed"
    case .disconnected: return "disconnected"
    case .closed: return "closed"
    case .count: return "count"
    @unknown default: return "unknown"
    }
  }
}

// MARK: - Connect Span

extension SignalingService {

  /// Wire values of the `webrtc.connect` span outcome.
  enum ConnectOutcome {
    case connected
    case failed
    case cancelled
    case skipped(state: String)
    case skippedUnexpected(state: String, iceState: String)

    nonisolated var rawValue: String {
      switch self {
      case .connected: "connected"
      case .failed: "failed"
      case .cancelled: "cancelled"
      case let .skipped(state): "skipped_\(state)"
      case let .skippedUnexpected(state, iceState): "skipped_\(state)_\(iceState)"
      }
    }
  }

  /// Why a `webrtc.connect` span ended as `failed`.
  enum ConnectFailureReason: String {
    case abandoned
    case maxReconnectsExceeded = "max_reconnects_exceeded"
  }

  /// One `webrtc.connect` span per peer covers the whole episode, retries included.
  /// `closePeerConnection` never ends it: a retry and the glare loser both continue on it.
  func startConnectSpan(for peer: String) {
    connectSpans[peer] = telemetry.startSpan(op: "webrtc.connect", attributes: ["role": connectRole(for: peer)])

    connectSpanAbandonTasks[peer]?.cancel()
    connectSpanAbandonTasks[peer] = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(Self.connectSpanAbandonAfter * 1_000_000_000))
      guard !Task.isCancelled, let self else { return }
      self.connectSpanAbandonTasks[peer] = nil
      self.finishConnectSpanAsFailed(peer, reason: .abandoned)
    }
  }

  /// `caller` when this side is the designated offerer; only meaningful once the username is known.
  func connectRole(for peer: String) -> String {
    shouldInitiateConnection(to: peer) ? "caller" : "callee"
  }

  /// Forgets a peer's span and its bookkeeping without ending it.
  func clearConnectSpan(_ peer: String) {
    connectSpanAbandonTasks[peer]?.cancel()
    connectSpanAbandonTasks[peer] = nil
    connectSpans[peer] = nil
    connectAttemptCounts[peer] = nil
  }

  /// Bumps the span's `attempts` attribute; a retry never opens a second span.
  func recordConnectAttempt(_ peer: String) {
    guard let span = connectSpans[peer] else { return }
    let next = (connectAttemptCounts[peer] ?? 0) + 1
    connectAttemptCounts[peer] = next
    telemetry.setAttributes(["attempts": next], on: span)
  }

  /// Ends a peer's span with an outcome and drops it from the map.
  func finishConnectSpan(
    _ peer: String,
    ok: Bool,
    outcome: ConnectOutcome,
    message: String? = nil,
    attributes: Telemetry.Attributes = [:],
  ) {
    guard let span = connectSpans[peer] else { return }
    clearConnectSpan(peer)
    telemetry.endSpan(span, ok: ok, outcome: outcome.rawValue, message: message, attributes: attributes)
  }

  /// Ends the span as skipped when a usable connection already exists.
  func finishConnectSpanAsSkipped(_ peer: String, existing pc: RTCPeerConnection) {
    let state = Self.name(pc.connectionState)
    let iceState = Self.name(pc.iceConnectionState)
    switch (pc.connectionState, pc.iceConnectionState) {
    case (.connected, _), (.connecting, _):
      finishConnectSpan(peer, ok: true, outcome: .skipped(state: state), message: state)
    case (.failed, _), (.disconnected, _), (_, .failed), (_, .disconnected):
      // A span with no attempt on it was opened by this very call; drop it rather than let it age out.
      if connectAttemptCounts[peer] == nil {
        clearConnectSpan(peer)
      }
    default:
      finishConnectSpan(peer, ok: true, outcome: .skippedUnexpected(state: state, iceState: iceState), message: "unexpected_state")
    }
  }

  /// Ends the span as failed with the connection state and candidate mix attached.
  func finishConnectSpanAsFailed(_ peer: String, reason: ConnectFailureReason) {
    guard connectSpans[peer] != nil else { return }
    let candidates = collectedCandidates[peer] ?? []
    var diagnostics: Telemetry.Attributes = [
      "failure_reason": reason.rawValue,
      "webrtc.peer_state": peerConnections[peer].map { Self.name($0.connectionState) } ?? "unknown",
      "webrtc.ice_state": peerConnections[peer].map { Self.name($0.iceConnectionState) } ?? "unknown",
      "webrtc.has_relay": candidates.contains("relay"),
      "webrtc.has_srflx": candidates.contains("srflx"),
      "webrtc.candidate_total": candidates.count,
    ]
    for (type, count) in candidateTypeCounts(for: peer) {
      diagnostics["webrtc.candidate.\(type)"] = count
    }
    finishConnectSpan(peer, ok: false, outcome: .failed, message: reason.rawValue, attributes: diagnostics)
  }

  /// Ends the span as connected, adding the selected ICE path once the stats report arrives.
  func finishConnectSpanAsSuccess(_ peer: String) {
    guard let span = connectSpans[peer] else { return }
    clearConnectSpan(peer)
    guard let pc = peerConnections[peer] else {
      telemetry.endSpan(span, ok: true, outcome: ConnectOutcome.connected.rawValue)
      return
    }

    let boxed = UnsafeSendable(value: (pc, span))
    Task.detached {
      var attributes: Telemetry.Attributes = [:]
      if let selected = await Self.selectedCandidateTypes(of: boxed.value.0) {
        attributes = [
          "webrtc.selected_path": selected.local,
          "webrtc.selected_remote_path": selected.remote,
          "webrtc.via_relay": selected.local == "relay" || selected.remote == "relay",
        ]
      }
      telemetry.endSpan(boxed.value.1, ok: true, outcome: ConnectOutcome.connected.rawValue, attributes: attributes)
    }
  }

  /// Reads the stats report off the main actor and picks the selected pair's candidate types.
  nonisolated static func selectedCandidateTypes(
    of pc: RTCPeerConnection,
  ) async -> (local: String, remote: String)? {
    await withCheckedContinuation { continuation in
      pc.statistics { report in
        continuation.resume(returning: Self.selectedCandidateTypes(in: report))
      }
    }
  }

  /// The selected candidate pair's local/remote kinds (host/srflx/prflx/relay).
  nonisolated static func selectedCandidateTypes(
    in report: RTCStatisticsReport,
  ) -> (local: String, remote: String)? {
    var selectedPairId: String?
    var pairs: [RTCStatistics] = []
    var candidateTypes: [String: String] = [:]

    for stat in report.statistics.values {
      switch stat.type {
      case "transport":
        selectedPairId = stat.values["selectedCandidatePairId"] as? String ?? selectedPairId
      case "candidate-pair":
        pairs.append(stat)
      case "local-candidate", "remote-candidate":
        candidateTypes[stat.id] = stat.values["candidateType"] as? String ?? "unknown"
      default:
        break
      }
    }

    let pair = selectedPairId.flatMap { id in pairs.first { $0.id == id } }
      ?? pairs.first { $0.values["state"] as? String == "succeeded" && ($0.values["nominated"] as? Bool ?? false) }
    guard
      let localId = pair?.values["localCandidateId"] as? String,
      let remoteId = pair?.values["remoteCandidateId"] as? String else { return nil }

    return (candidateTypes[localId] ?? "unknown", candidateTypes[remoteId] ?? "unknown")
  }
}
