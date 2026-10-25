//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation
@preconcurrency import WebRTC
@testable import PastePoint

@MainActor
final class MockWebRTCEngine: WebRTCEngine {
  var failsToConnect = false
  private(set) var connections: [RTCPeerConnection] = []
  private(set) var closed: Set<ObjectIdentifier> = []
  private(set) var sentFrames: [Data] = []
  private var isPaused = false
  private var waitingConnections: [CheckedContinuation<Void, Never>] = []
  private let factory = RTCPeerConnectionFactory()

  var liveConnections: [RTCPeerConnection] {
    connections.filter { !closed.contains(ObjectIdentifier($0)) }
  }

  var pausedConnections: Int {
    waitingConnections.count
  }

  func pauseNewConnections() {
    isPaused = true
  }

  func resumeNewConnections() {
    isPaused = false
    let waiting = waitingConnections
    waitingConnections = []
    waiting.forEach { $0.resume() }
  }

  func makePeerConnection(iceServers: [RTCIceServer], delegate: RTCPeerConnectionDelegate) async -> RTCPeerConnection? {
    if isPaused {
      await withCheckedContinuation { waitingConnections.append($0) }
    }
    guard !failsToConnect else { return nil }
    let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
    let pc = factory.peerConnection(with: RTCConfiguration(), constraints: constraints, delegate: nil)
    if let pc { connections.append(pc) }
    return pc
  }

  func makeDataChannel(on pc: RTCPeerConnection, label: String) async -> RTCDataChannel? {
    pc.dataChannel(forLabel: label, configuration: WebRTCConfig.dataChannelConfig)
  }

  func makeLocalDescription(_ type: RTCSdpType, on pc: RTCPeerConnection) async throws -> String {
    type == .offer ? "offer" : "answer"
  }

  func setRemoteDescription(_ type: RTCSdpType, sdp: String, on pc: RTCPeerConnection) async throws {}

  func add(_ candidate: RTCIceCandidate, to pc: RTCPeerConnection) async throws {}

  func states(of pc: RTCPeerConnection) async -> (peer: RTCPeerConnectionState, ice: RTCIceConnectionState) {
    (.new, .new)
  }

  func send(_ data: Data, on channel: RTCDataChannel) {
    sentFrames.append(data)
  }

  func sendChunk(_ data: Data, on channel: RTCDataChannel) async -> Bool {
    sentFrames.append(data)
    return true
  }

  func close(_ pc: RTCPeerConnection?, channel: RTCDataChannel?) {
    if let pc { closed.insert(ObjectIdentifier(pc)) }
    if let channel { closed.insert(ObjectIdentifier(channel)) }
  }
}
