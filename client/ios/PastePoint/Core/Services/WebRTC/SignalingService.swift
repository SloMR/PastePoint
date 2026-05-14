//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Combine
import Foundation
import Logging
import WebRTC

private struct UnsafeSendable<T>: @unchecked Sendable {
  nonisolated(unsafe) let value: T
  nonisolated init(value: T) { self.value = value }
}

@MainActor
final class SignalingService: NSObject, ObservableObject {
  private let logger = Logger(label: "SignalingService")
  
  @Published private(set) var connectedPeers: Set<String> = []
  
  private var peerConnections: [String: RTCPeerConnection] = [:]
  private var dataChannels: [String: RTCDataChannel] = [:]
  
  private let wsService: WebSocketConnectionService
  private let userService: UserService
  
  private var cancellables: Set<AnyCancellable> = []
  
  init(wsService: WebSocketConnectionService, userService: UserService) {
    self.wsService = wsService
    self.userService = userService
    super.init()
    
    wsService.signalMessage
      .receive(on: DispatchQueue.main)
      .sink { [weak self] message in
        self?.handle(message)
      }
      .store(in: &cancellables)
  }
  
// MARK: -
  
  private func handle(_ message: SignalMessage) {
    logger.info("handle: received \(message.type.rawValue) from \(message.from)")
    switch message.type {
    case .offer:
      Task {
        await handleOffer(message)
      }
    case .answer:
      Task {
        await handleAnswer(message)
      }
    case .candidate:
      Task {
        await handleCandidate(message)
      }
    case .connectionRequest:
      break // Step 5
    }
  }
  
// MARK: -

  func initiateConnection(to peer: String) async {
    guard peerConnections[peer] == nil else {
      logger.warning("initiateConnection: already have a connection to \(peer)")
      return
    }
    
    guard let pc = PeerConnectionFactory.shared.makePeerConnection(delegate: self) else {
      logger.error("initiateConnection: factory returned nil for \(peer)")
      return
    }
    peerConnections[peer] = pc
    
    guard let channel = pc.dataChannel(forLabel: "data", configuration: WebRTCConfig.dataChannelConfig) else {
      logger.error("initiateConnection: failed to create data channel for \(peer)")
      peerConnections[peer] = nil
      return
    }
    channel.delegate = self
    dataChannels[peer] = channel
    
    let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
    do {
      let offer = try await pc.offer(for: constraints)
      try await pc.setLocalDescription(offer)
    } catch {
      logger.error("initiateConnection: SDP offer failed: \(error.localizedDescription)")
      peerConnections[peer] = nil
      dataChannels[peer] = nil
      return
    }
    
    let payload: [String: Any] = [
      "type": "offer",
      "data": ["type": "offer", "sdp": pc.localDescription?.sdp ?? ""],
      "from": userService.user,
      "to": peer
    ]
    await wsService.sendSignal(payload)
    logger.info("initiateConnection: offer sent to \(peer)")
  }
  
  func send(_ text: String, to peer: String) {
    guard let channel = dataChannels[peer] else {
      logger.warning("send: no data channel for \(peer)")
      return
    }
    
    guard channel.readyState == .open else {
      logger.warning("send: channel to \(peer) not open (state :\(channel.readyState.rawValue))")
      return
    }
    
    let buffer = RTCDataBuffer(data: Data(text.utf8), isBinary: false)
    channel.sendData(buffer)
    logger.info("send: sent \(text) to \(peer)")
  }
  
// MARK: -

  private func handleOffer(_ message: SignalMessage) async {
    guard let remoteSdp = parseSdp(from: message.data, type: .offer) else {
      logger.error("handleOffer: malformed SDP from \(message.from)")
      return
    }
    
    guard let pc = PeerConnectionFactory.shared.makePeerConnection(delegate: self) else {
      logger.error("handleOffer: factory returned nil for \(message.from)")
      return
    }
    peerConnections[message.from] = pc
    
    do {
      try await pc.setRemoteDescription(remoteSdp)
      let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
      let answer = try await pc.answer(for: constraints)
      try await pc.setLocalDescription(answer)
    } catch {
      logger.error("handleOffer: SDP exchange failed: \(error.localizedDescription)")
      peerConnections[message.from] = nil
      return
    }
    
    let payload: [String: Any] = [
      "type": "answer",
      "data": ["type": "answer", "sdp": pc.localDescription?.sdp ?? ""],
      "from": userService.user,
      "to": message.from,
    ]
    await wsService.sendSignal(payload)
    logger.info("handleOffer: answer sent to \(message.from)")
  }
  
  private func handleAnswer(_ message: SignalMessage) async {
    guard let pc = peerConnections[message.from] else {
      logger.warning("handleAnswer: no peer connection for \(message.from)")
      return
    }
    
    guard let remoteSdp = parseSdp(from: message.data, type: .answer) else {
      logger.error("handleAnswer: malformed SDP from \(message.from)")
      return
    }
    
    do {
      try await pc.setRemoteDescription(remoteSdp)
      logger.info("handleAnswer: remote description set for \(message.from)")
    } catch {
      logger.error("handleAnswer: setRemoteDescription failed: \(error.localizedDescription)")
    }
  }
  
  private func handleCandidate(_ message: SignalMessage) async {
    guard let pc = peerConnections[message.from] else {
      logger.warning("handleCandidate: no peer connection for \(message.from)")
      return
    }
    
    guard let candidate = parseCandidate(from: message.data) else {
      logger.error("handleCandidate: malformed candidate from \(message.from)")
      return
    }
    
    do {
      try await pc.add(candidate)
      logger.info("handleCandidate: candidate added for \(message.from)")
    } catch {
      logger.error("handleCandidate: add failed: \(error.localizedDescription)")
    }
  }
  
// MARK: -

  // TODO: Remove this parseing and modify the Any object type
  private func parseSdp(from data: Any?, type: RTCSdpType) -> RTCSessionDescription? {
    guard
      let dict = data as? [String: Any],
      let sdp = dict["sdp"] as? String
    else { return nil }
    return RTCSessionDescription(type: type, sdp: sdp)
  }
  
  // TODO: Remove this parseing and modify the Any object type
  private func parseCandidate(from data: Any?) -> RTCIceCandidate? {
    guard
      let dict = data as? [String: Any],
      let candidate = dict["candidate"] as? String
    else { return nil }
    let sdpMid = dict["sdpMid"] as? String
    let sdpMLineIndex = (dict["sdpMLineIndex"] as? Int).map(Int32.init) ?? 0
    return RTCIceCandidate(sdp: candidate, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
  }
  
  private func peer(forConnectionID id: ObjectIdentifier) -> String? {
    peerConnections.first(where: { ObjectIdentifier($0.value) == id })?.key
  }

  private func peer(forChannelID id: ObjectIdentifier) -> String? {
    dataChannels.first(where: { ObjectIdentifier($0.value) == id })?.key
  }
}

// MARK: -

extension SignalingService: RTCPeerConnectionDelegate, RTCDataChannelDelegate {
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
  nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
    let peerConnectionID = ObjectIdentifier(peerConnection)
    let sdp = candidate.sdp
    let sdpMid = candidate.sdpMid
    let sdpMLineIndex = candidate.sdpMLineIndex

    Task { @MainActor [weak self] in
      guard let self else { return }

      guard let peer = self.peer(forConnectionID: peerConnectionID) else {
        self.logger.warning("didGenerate: unknown peer connection")
        return
      }
      
      let payload: [String: Any] = [
        "type": "candidate",
        "data": [
          "candidate": sdp,
          "sdpMid": sdpMid ?? "",
          "sdpMLineIndex": Int(sdpMLineIndex)
        ],
        "from": self.userService.user,
        "to": peer
      ]
      await self.wsService.sendSignal(payload)
    }
  }

  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
    let peerConnectionID = ObjectIdentifier(peerConnection)
    let box = UnsafeSendable(value: dataChannel)
    
    Task { @MainActor [weak self] in
      guard let self else { return }
      
      guard let peer = self.peer(forConnectionID: peerConnectionID) else {
        self.logger.warning("didOpen: unknown peer connection")
        return
      }
      
      box.value.delegate = self
      self.dataChannels[peer] = box.value
      self.logger.info("didOpen: data channel attached to peer: \(peer)")
    }
  }

  nonisolated func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
    let dataChannelID = ObjectIdentifier(dataChannel)
    let state = dataChannel.readyState

    Task { @MainActor [weak self] in
      guard let self else { return }
      
      guard let peer = self.peer(forChannelID: dataChannelID) else {
        self.logger.warning("dataChannelDidChangeState: unknown channel")
        return
      }
      
      switch state {
      case .open:
        self.connectedPeers.insert(peer)
        self.logger.info("dataChannelDidChangeState: connected to \(peer)")
      case .closed:
        self.connectedPeers.remove(peer)
        self.logger.info("dataChannelDidChangeState: disconnected from \(peer)")
      case .connecting:
        self.logger.info("dataChannelDidChangeState: connecting to \(peer)")
        break
      case .closing:
        self.logger.info("dataChannelDidChangeState: closing connection to \(peer)")
        break
      @unknown default:
        break
      }
      
    }
  }

  nonisolated func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
    let dataChannelID = ObjectIdentifier(dataChannel)
    let bytes = buffer.data
    let isBinary = buffer.isBinary

    Task { @MainActor [weak self] in
      guard let self else { return }
      
      guard let peer = self.peer(forChannelID: dataChannelID) else {
        self.logger.warning("didReceiveMessag: unknown channel")
        return
      }
      
      if isBinary {
        self.logger.info("didReceiveMessageWith: received \(bytes.count) bytes from \(peer)")
      } else {
        let text = String(decoding: bytes, as: UTF8.self)
        self.logger.info("didReceiveMessageWith: received from \(peer): \(text)")
      }
    }
  }
}
