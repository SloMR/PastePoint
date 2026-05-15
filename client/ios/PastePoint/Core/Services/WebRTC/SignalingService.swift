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
  
  private var outboundSequences: [String: Int] = [:]
  private var inboundSequences: [String: Int] = [:]

  private var peerConnections: [String: RTCPeerConnection] = [:]
  private var dataChannels: [String: RTCDataChannel] = [:]
  private var candidateQueues: [String: [RTCIceCandidate]] = [:]
  private var connectionLocks: Set<String> = []
  
  private var reconnectAttemps: [String: Int] = [:]
  private var reconnectTask: [String: Task<Void, Never>] = [:]
  
  let bufferedAmountLow = PassthroughSubject<String, Never>()
  
  private static let maxReconnectAttempts = 5
  private static let baseReconnectDelay: TimeInterval = 2.0 // Seconds
  private static let maxReconnectDelay: TimeInterval = 10.0 // Seconds
  
  private let wsService: WebSocketConnectionService
  private let userService: UserService
  private let peerDirectory: PeerDirectory
  
  private var cancellables: Set<AnyCancellable> = []
  
  init(wsService: WebSocketConnectionService, userService: UserService, peerDirectory: PeerDirectory) {
    self.wsService = wsService
    self.userService = userService
    self.peerDirectory = peerDirectory
    super.init()
    
    wsService.signalMessage
      .receive(on: DispatchQueue.main)
      .sink { [weak self] message in
        self?.handle(message)
      }
      .store(in: &cancellables)
    
    peerDirectory.$peers
      .receive(on: DispatchQueue.main)
      .sink { [weak self] peers in
        self?.syncMesh(peers: peers)
      }
      .store(in: &cancellables)
  }
  
// MARK: -
  
  private func handle(_ message: SignalMessage) {
    guard !message.from.isEmpty else {
      logger.warning("handle: ignoring message with empty 'from'")
      return
    }

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
      Task {
        await handleConnectionRequest(message)
      }
    }
  }
  
// MARK: -

  func initiateConnection(to peer: String) async {
    guard !connectionLocks.contains(peer) else {
      logger.debug("initiateConnection: already locked for \(peer)")
      return
    }

    guard peerConnections[peer] == nil else {
      logger.warning("initiateConnection: already have a connection to \(peer)")
      return
    }

    await waitForUsername()
    if !shouldInitiateConnection(to: peer) {
      logger.info("initiateConnection: not the designated caller for \(peer), sending connection request")
      await wsService.sendSignal([
        "type": "connection_request",
        "data": [:] as [String: Any],
        "from": userService.user,
        "to": peer,
        "sequence": nextSequence(for: peer)
      ])
      return
    }

    connectionLocks.insert(peer)
    guard let pc = PeerConnectionFactory.shared.makePeerConnection(delegate: self) else {
      logger.error("initiateConnection: factory returned nil for \(peer)")
      connectionLocks.remove(peer)
      return
    }
    peerConnections[peer] = pc
    
    guard let channel = pc.dataChannel(forLabel: "data", configuration: WebRTCConfig.dataChannelConfig) else {
      logger.error("initiateConnection: failed to create data channel for \(peer)")
      peerConnections[peer] = nil
      connectionLocks.remove(peer)
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
      connectionLocks.remove(peer)
      return
    }
    
    let payload: [String: Any] = [
      "type": "offer",
      "data": ["type": "offer", "sdp": pc.localDescription?.sdp ?? ""],
      "from": userService.user,
      "to": peer,
      "sequence": nextSequence(for: peer)
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
  
  private func syncMesh(peers: [String]) {
    let target = Set(peers)
    let tracked = Set(peerConnections.keys).union(connectionLocks)
    
    let toOpen = target.subtracting(tracked)
    let toClose = tracked.subtracting(target)
    
    for peer in toClose {
      logger.info("syncMesh: closing connection to \(peer) (left room)")
      closePeerConnection(peer)
    }
    
    for peer in toOpen {
      logger.info("syncMesh: opening connection to \(peer) (joined room)")
      Task {
        await initiateConnection(to: peer)
      }
    }
  }
  
// MARK: -
  
  private func scheduleReconnect(to peer: String) {
    if reconnectTask[peer] != nil { // TODO: Convert to guard
      logger.debug("scheduleReconnect: already scheduled for \(peer)")
      return
    }
    
    // Only connect if the peer is still expected to be in the room
    guard peerDirectory.peers.contains(peer) else {
      logger.info("scheduleReconnect: \(peer) is no longer a peer, skipping")
      reconnectAttemps[peer] = nil
      return
    }
    
    let attempts = reconnectAttemps[peer] ?? 0
    guard attempts < Self.maxReconnectAttempts else {
      logger.error("scheduleReconnect: max attempts reached for \(peer)")
      reconnectAttemps[peer] = nil
      return
    }
    
    reconnectAttemps[peer] = attempts + 1
    
    // Exponential backoff: 2s, 3s, 4.5s, ...
    let delay = min(Self.baseReconnectDelay * pow(1.5, Double(attempts)), Self.maxReconnectDelay)
    logger.warning("scheduleReconnect: attempt \(attempts + 1) for \(peer) in \(delay)s")
    
    reconnectTask[peer] = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      if Task.isCancelled { return }
      guard let self else { return }
      self.reconnectTask[peer] = nil
      
      guard self.peerDirectory.peers.contains(peer) else {
        self.logger.info("scheduleReconnect: \(peer) left during backoff, skipping")
        self.reconnectAttemps[peer] = nil
        return
      }
      
      // Don't reconnect if we have already healed since scheduling
      if self.connectedPeers.contains(peer) {
        self.logger.debug("scheduleReconnect: \(peer) already healthy, skipping")
        self.reconnectAttemps[peer] = nil
        return
      }
      
      self.logger.info("scheduleReconnect: reconnecting to \(peer)")
      self.closePeerConnection(peer)
      await self.initiateConnection(to: peer)
    }
    
  }
  
// MARK: -

  private func handleOffer(_ message: SignalMessage) async {
    await waitForUsername()

    if isDuplicate(message.from, sequence: message.sequence) {
      logger.debug("handleOffer: ignoring duplicate sequence from \(message.from)")
      return
    }
    
    if connectionLocks.contains(message.from) {
      logger.warning("handleOffer: collision with \(message.from), resolving by role")
      if shouldInitiateConnection(to: message.from) {
        logger.debug("handleOffer: ignoring offer from \(message.from) (we are the designated caller)")
        return
      } else {
        logger.debug("handleOffer: canceling our initiation for \(message.from) (we are the designated callee)")
        closePeerConnection(message.from)
      }
    }
    connectionLocks.insert(message.from)

    guard let remoteSdp = parseSdp(from: message.data, type: .offer) else {
      logger.error("handleOffer: malformed SDP from \(message.from)")
      connectionLocks.remove(message.from)
      return
    }
    
    guard let pc = PeerConnectionFactory.shared.makePeerConnection(delegate: self) else {
      logger.error("handleOffer: factory returned nil for \(message.from)")
      connectionLocks.remove(message.from)
      return
    }
    peerConnections[message.from] = pc
    
    do {
      try await pc.setRemoteDescription(remoteSdp)
      await drainCandidateQueue(for: message.from)
      let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
      let answer = try await pc.answer(for: constraints)
      try await pc.setLocalDescription(answer)
    } catch {
      logger.error("handleOffer: SDP exchange failed: \(error.localizedDescription)")
      peerConnections[message.from] = nil
      connectionLocks.remove(message.from)
      return
    }
    
    let payload: [String: Any] = [
      "type": "answer",
      "data": ["type": "answer", "sdp": pc.localDescription?.sdp ?? ""],
      "from": userService.user,
      "to": message.from,
      "sequence": nextSequence(for: message.from)
    ]
    await wsService.sendSignal(payload)
    logger.info("handleOffer: answer sent to \(message.from)")
  }
  
  private func handleAnswer(_ message: SignalMessage) async {
    if isDuplicate(message.from, sequence: message.sequence) {
      logger.debug("handleAnswer: ignoring duplicate sequence from \(message.from)")
      return
    }

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
      await drainCandidateQueue(for: message.from)
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
    
    if pc.remoteDescription != nil {
      do {
        try await pc.add(candidate)
        logger.info("handleCandidate: candidate added for \(message.from)")
      } catch {
        logger.error("handleCandidate: add failed: \(error.localizedDescription)")
      }
    } else {
      if candidateQueues[message.from] == nil {
        candidateQueues[message.from] = []
      }
      candidateQueues[message.from]?.append(candidate)
      logger.info("handleCandidate: queued candidate for \(message.from) (queue size: \(candidateQueues[message.from]?.count ?? 0))")
    }
  }
  
  private func handleConnectionRequest(_ message: SignalMessage) async {
    if isDuplicate(message.from, sequence: message.sequence) {
      logger.debug("handleConnectionRequest: ignoring duplicate sequence from \(message.from)")
      return
    }

    logger.info("handleConnectionRequest: \(message.from) is asking us to initiate")
    await initiateConnection(to: message.from)
  }
  
// MARK: -

  private func drainCandidateQueue(for peer: String) async {
    guard let pc = peerConnections[peer] else { return }
    guard let queued = candidateQueues[peer], !queued.isEmpty else { return }
    
    candidateQueues[peer] = nil
    
    for candidate in queued {
      do {
        try await pc.add(candidate)
      } catch {
        logger.error("drainCandidateQueue: add failed for \(peer)")
      }
    }
    logger.info("drainCandidateQueue: drained \(queued.count) candidates for \(peer)")
  }
  
  private func closePeerConnection(_ peer: String) {
    reconnectTask[peer]?.cancel()
    reconnectTask[peer] = nil
    reconnectAttemps[peer] = nil
    dataChannels[peer]?.close()
    dataChannels[peer] = nil
    peerConnections[peer]?.close()
    peerConnections[peer] = nil
    candidateQueues[peer] = nil
    connectionLocks.remove(peer)
    connectedPeers.remove(peer)
  }
  
  func isReadyToSend(to peer: String) -> Bool {
    guard let channel = dataChannels[peer], channel.readyState == .open else {
      return false
    }
    
    return channel.bufferedAmount < WebRTCConfig.maxBufferedAmount
  }
  
  private func waitForUsername() async {
    if !userService.user.isEmpty { return }
    for await user in userService.$user.values where !user.isEmpty {
      return
    }
  }
  
  private func nextSequence(for peer: String) -> Int {
    let next = (outboundSequences[peer] ?? 0) + 1
    outboundSequences[peer] = next
    return next
  }
  
  private func isDuplicate(_ peer: String, sequence: Int?) -> Bool {
    guard let sequence else { return false }
    let last = inboundSequences[peer] ?? 0
    if sequence <= last { return true }
    inboundSequences[peer] = sequence
    return false
  }
  
  private func shouldInitiateConnection(to peer: String) -> Bool {
    return userService.user.localizedCompare(peer) == .orderedAscending
  }
  
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
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
    let peerConnectionID = ObjectIdentifier(peerConnection)
    let state = newState
    
    Task { @MainActor [weak self] in
      guard let self else { return }
      guard let peer = self.peer(forConnectionID: peerConnectionID) else { return }
      
      self.logger.debug("iceConnectionState: \(peer) → \(state.rawValue)")
      switch state {
      case .failed, .disconnected:
        self.scheduleReconnect(to: peer)
      case .closed:
        self.connectedPeers.remove(peer)
      default:
        break
      }
    }
  }
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
    let peerConnectionID = ObjectIdentifier(peerConnection)
    let sdp = candidate.sdp
    let sdpMid = candidate.sdpMid
    let sdpMLineIndex = candidate.sdpMLineIndex

    Task { @MainActor [weak self] in
      guard let self else { return }
      await waitForUsername()

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
        "to": peer,
        "sequence": nextSequence(for: peer)
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
        self.logger.debug("dataChannelDidChangeState: unknown channel (already closed)")
        return
      }
      
      switch state {
      case .open:
        self.connectedPeers.insert(peer)
        self.connectionLocks.remove(peer)
        self.reconnectAttemps[peer] = nil
        self.logger.info("dataChannelDidChangeState: connected to \(peer)")
      case .closed:
        self.connectedPeers.remove(peer)
        self.connectionLocks.remove(peer)
        self.logger.info("dataChannelDidChangeState: disconnected from \(peer)")
        self.scheduleReconnect(to: peer)
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
        self.logger.warning("didReceiveMessageWith: unknown channel")
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
  
  nonisolated func dataChannel(_ dataChannel: RTCDataChannel, didChangeBufferedAmount amount: UInt64) {
    let dataChannelID = ObjectIdentifier(dataChannel)
    let currentBuffered = dataChannel.bufferedAmount
    
    Task { @MainActor [weak self] in
      guard let self else { return }
      guard let peer = self.peer(forChannelID: dataChannelID) else { return }
      
      if currentBuffered < WebRTCConfig.bufferedAmountLowThreshold {
        self.logger.debug("dataChannel: buffer low for \(peer) (\(currentBuffered) bytes)")
        self.bufferedAmountLow.send(peer)
      }
    }
  }
}
