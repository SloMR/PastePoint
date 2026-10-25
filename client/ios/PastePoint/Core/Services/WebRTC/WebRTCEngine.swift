//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation
@preconcurrency import WebRTC

protocol WebRTCEngine {
  func makePeerConnection(iceServers: [RTCIceServer], delegate: RTCPeerConnectionDelegate) async -> RTCPeerConnection?
  func makeDataChannel(on pc: RTCPeerConnection, label: String) async -> RTCDataChannel?
  func makeLocalDescription(_ type: RTCSdpType, on pc: RTCPeerConnection) async throws -> String
  func setRemoteDescription(_ type: RTCSdpType, sdp: String, on pc: RTCPeerConnection) async throws
  func add(_ candidate: RTCIceCandidate, to pc: RTCPeerConnection) async throws
  func states(of pc: RTCPeerConnection) async -> (peer: RTCPeerConnectionState, ice: RTCIceConnectionState)
  func send(_ data: Data, on channel: RTCDataChannel)
  func sendChunk(_ data: Data, on channel: RTCDataChannel) async -> Bool
  func close(_ pc: RTCPeerConnection?, channel: RTCDataChannel?)
}

struct DefaultWebRTCEngine: WebRTCEngine {
  func makePeerConnection(iceServers: [RTCIceServer], delegate: RTCPeerConnectionDelegate) async -> RTCPeerConnection? {
    await PeerConnectionFactory.shared.makePeerConnection(iceServers: iceServers, delegate: delegate)
  }

  func makeDataChannel(on pc: RTCPeerConnection, label: String) async -> RTCDataChannel? {
    await WebRTCQueue.makeDataChannel(on: pc, label: label)
  }

  func makeLocalDescription(_ type: RTCSdpType, on pc: RTCPeerConnection) async throws -> String {
    try await WebRTCQueue.makeLocalDescription(type, on: pc)
  }

  func setRemoteDescription(_ type: RTCSdpType, sdp: String, on pc: RTCPeerConnection) async throws {
    try await WebRTCQueue.setRemoteDescription(type, sdp: sdp, on: pc)
  }

  func add(_ candidate: RTCIceCandidate, to pc: RTCPeerConnection) async throws {
    try await WebRTCQueue.add(candidate, to: pc)
  }

  func states(of pc: RTCPeerConnection) async -> (peer: RTCPeerConnectionState, ice: RTCIceConnectionState) {
    await WebRTCQueue.states(of: pc)
  }

  func send(_ data: Data, on channel: RTCDataChannel) {
    WebRTCQueue.send(data, on: channel)
  }

  func sendChunk(_ data: Data, on channel: RTCDataChannel) async -> Bool {
    await WebRTCQueue.sendChunk(data, on: channel)
  }

  func close(_ pc: RTCPeerConnection?, channel: RTCDataChannel?) {
    WebRTCQueue.close(pc, channel: channel)
  }
}
