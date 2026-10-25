//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation
import WebRTC

// MARK: - RTCPeerConnectionDelegate

extension SignalingService: RTCPeerConnectionDelegate {

  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
  nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didFailToGatherIceCandidate event: RTCIceCandidateErrorEvent) {
    guard event.url.hasPrefix("turn") else { return }
    log.warning("relay candidate failed: \(event.errorCode) \(event.errorText) (\(event.url))")
  }

  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
    guard newState == .complete else { return }
    let peerConnectionID = ObjectIdentifier(peerConnection)

    Task { @MainActor [weak self] in
      guard let self, let peer = self.peer(forConnectionID: peerConnectionID) else { return }
      telemetry.breadcrumb(
        category: "webrtc.ice",
        message: "ice gathering complete",
        data: ["types": self.candidateTypeCounts(for: peer)],
      )
    }
  }

  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
    let peerConnectionID = ObjectIdentifier(peerConnection)
    let state = newState

    Task { @MainActor [weak self] in
      guard let self, self.peer(forConnectionID: peerConnectionID) != nil else { return }
      telemetry.breadcrumb(
        category: "webrtc.peer",
        message: "peer connection state: \(Self.name(state))",
        level: state == .failed ? .error : .info,
      )
    }
  }

  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
    let peerConnectionID = ObjectIdentifier(peerConnection)
    let state = newState

    Task { @MainActor [weak self] in
      guard let self else { return }
      guard let peer = self.peer(forConnectionID: peerConnectionID) else { return }

      log.debug("iceConnectionState: \(peer) → \(state.rawValue)")
      telemetry.breadcrumb(
        category: "webrtc.ice",
        message: "ice connection state: \(Self.name(state))",
        level: state == .failed ? .error : .info,
      )
      switch state {
      case .checking:
        telemetry.markElapsed("webrtc.ice_checking_ms", on: self.connectSpans[peer])
      case .connected, .completed:
        telemetry.markElapsed("webrtc.ice_connected_ms", on: self.connectSpans[peer])
      case .failed, .disconnected:
        self.scheduleReconnect(to: peer)
      case .closed:
        self.connectedPeers.remove(peer)
      default:
        break
      }
    }
  }

  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
    let peerConnectionID = ObjectIdentifier(peerConnection)
    let sdp = candidate.sdp
    let sdpMid = candidate.sdpMid
    let sdpMLineIndex = candidate.sdpMLineIndex

    Task { @MainActor [weak self] in
      guard let self else { return }
      await userService.waitForUsername()

      guard let peer = self.peer(forConnectionID: peerConnectionID) else {
        log.warning("unknown peer connection")
        return
      }

      self.collectedCandidates[peer, default: []].append(self.candidateType(from: sdp))

      let candidateMessage = SignalMessage(
        payload: .candidate(sdp: sdp, sdpMid: sdpMid, sdpMLineIndex: sdpMLineIndex),
        from: self.userService.user,
        to: peer,
      )
      await self.wsService.sendSignal(candidateMessage)
    }
  }

  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
    let peerConnectionID = ObjectIdentifier(peerConnection)
    let box = UnsafeSendable(value: dataChannel)

    // Read here on libwebrtc's thread; the same read on the main actor would block.
    let isOpen = dataChannel.readyState == .open

    Task { @MainActor [weak self] in
      guard let self else { return }

      guard let peer = self.peer(forConnectionID: peerConnectionID) else {
        log.warning("unknown peer connection")
        self.webRTC.close(nil, channel: box.value)
        return
      }

      box.value.delegate = self
      if let previous = self.dataChannels.updateValue(box.value, forKey: peer) {
        self.webRTC.close(nil, channel: previous)
      }
      log.info("data channel attached")
      if isOpen {
        self.handleChannelOpened(peer)
      }
    }
  }
}
