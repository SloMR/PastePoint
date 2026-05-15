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

  private var reconnectAttempts: [String: Int] = [:]
  private var reconnectTasks: [String: Task<Void, Never>] = [:]

  private var connectionTimeouts: [String: Task<Void, Never>] = [:]
  private static let connectionTimeout: TimeInterval = 30.0 // Seconds

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
      logger.warning("ignoring message with empty 'from'")
      return
    }

    logger.info("received \(message.payload.typeString) from \(message.from)")
    switch message.payload {
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
      logger.debug("already locked for \(peer)")
      return
    }

    guard peerConnections[peer] == nil else {
      logger.warning("already have a connection to \(peer)")
      return
    }

    await waitForUsername()
    if !shouldInitiateConnection(to: peer) {
      logger.info("not the designated caller for \(peer), sending connection request")
      let request = SignalMessage(
        payload: .connectionRequest,
        from: userService.user,
        to: peer,
        sequence: nextSequence(for: peer),
      )
      await wsService.sendSignal(request)
      return
    }

    connectionLocks.insert(peer)
    startConnectionTimeout(for: peer)

    guard let pc = PeerConnectionFactory.shared.makePeerConnection(delegate: self) else {
      logger.error("factory returned nil for \(peer)")
      connectionLocks.remove(peer)
      return
    }
    peerConnections[peer] = pc

    guard let channel = pc.dataChannel(forLabel: "data", configuration: WebRTCConfig.dataChannelConfig) else {
      logger.error("failed to create data channel for \(peer)")
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
      logger.error("SDP offer failed: \(error.localizedDescription)")
      peerConnections[peer] = nil
      dataChannels[peer] = nil
      connectionLocks.remove(peer)
      return
    }

    let offerMessage = SignalMessage(
      payload: .offer(sdp: pc.localDescription?.sdp ?? ""),
      from: userService.user,
      to: peer,
      sequence: nextSequence(for: peer),
    )
    await wsService.sendSignal(offerMessage)
    logger.info("offer sent to \(peer)")
  }

  func send(_ text: String, to peer: String) {
    guard let channel = dataChannels[peer] else {
      logger.warning("no data channel for \(peer)")
      return
    }

    guard channel.readyState == .open else {
      logger.warning("channel to \(peer) not open (state: \(channel.readyState.rawValue))")
      return
    }

    let buffer = RTCDataBuffer(data: Data(text.utf8), isBinary: false)
    channel.sendData(buffer)
    logger.info("sent \(text) to \(peer)")
  }

  private func syncMesh(peers: [String]) {
    let target = Set(peers)
    let tracked = Set(peerConnections.keys).union(connectionLocks)

    let toOpen = target.subtracting(tracked)
    let toClose = tracked.subtracting(target)

    for peer in toClose {
      logger.info("closing connection to \(peer) (left room)")
      closePeerConnection(peer)
    }

    for peer in toOpen {
      logger.info("opening connection to \(peer) (joined room)")
      Task {
        await initiateConnection(to: peer)
      }
    }
  }

  // MARK: -

  private func scheduleReconnect(to peer: String) {
    if reconnectTasks[peer] != nil { // TODO: Convert to guard
      logger.debug("already scheduled for \(peer)")
      return
    }

    // Only connect if the peer is still expected to be in the room
    guard peerDirectory.peers.contains(peer) else {
      logger.info("\(peer) is no longer a peer, skipping")
      reconnectAttempts[peer] = nil
      return
    }

    let attempts = reconnectAttempts[peer] ?? 0
    guard attempts < Self.maxReconnectAttempts else {
      logger.error("max attempts reached for \(peer)")
      reconnectAttempts[peer] = nil
      return
    }

    reconnectAttempts[peer] = attempts + 1

    // Exponential backoff: 2s, 3s, 4.5s, ...
    let delay = min(Self.baseReconnectDelay * pow(1.5, Double(attempts)), Self.maxReconnectDelay)
    logger.warning("attempt \(attempts + 1) for \(peer) in \(delay)s")

    reconnectTasks[peer] = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      if Task.isCancelled { return }
      guard let self else { return }
      self.reconnectTasks[peer] = nil

      guard self.peerDirectory.peers.contains(peer) else {
        self.logger.info("\(peer) left during backoff, skipping")
        self.reconnectAttempts[peer] = nil
        return
      }

      // Don't reconnect if we have already healed since scheduling
      if self.connectedPeers.contains(peer) {
        self.logger.debug("\(peer) already healthy, skipping")
        self.reconnectAttempts[peer] = nil
        return
      }

      self.logger.info("reconnecting to \(peer)")
      self.closePeerConnection(peer, resetReconnectState: false)
      await self.initiateConnection(to: peer)
    }

  }

  // MARK: -

  private func handleOffer(_ message: SignalMessage) async {
    await waitForUsername()

    if isDuplicate(message.from, sequence: message.sequence) {
      logger.debug("ignoring duplicate sequence from \(message.from)")
      return
    }

    if connectionLocks.contains(message.from) {
      logger.warning("collision with \(message.from), resolving by role")
      if shouldInitiateConnection(to: message.from) {
        logger.debug("ignoring offer from \(message.from) (we are the designated caller)")
        return
      } else {
        logger.debug("canceling our initiation for \(message.from) (we are the designated callee)")
        closePeerConnection(message.from)
      }
    }

    connectionLocks.insert(message.from)
    startConnectionTimeout(for: message.from)

    guard case .offer(let sdpString) = message.payload else {
      logger.error("payload is not .offer (received \(message.payload.typeString))")
      return
    }
    let remoteSdp = RTCSessionDescription(type: .offer, sdp: sdpString)

    guard let pc = PeerConnectionFactory.shared.makePeerConnection(delegate: self) else {
      logger.error("factory returned nil for \(message.from)")
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
      logger.error("SDP exchange failed: \(error.localizedDescription)")
      peerConnections[message.from] = nil
      connectionLocks.remove(message.from)
      return
    }

    let response = SignalMessage(
      payload: .answer(sdp: pc.localDescription?.sdp ?? ""),
      from: userService.user,
      to: message.from,
      sequence: nextSequence(for: message.from),
    )
    await wsService.sendSignal(response)
    logger.info("answer sent to \(message.from)")
  }

  private func handleAnswer(_ message: SignalMessage) async {
    if isDuplicate(message.from, sequence: message.sequence) {
      logger.debug("ignoring duplicate sequence from \(message.from)")
      return
    }

    guard let pc = peerConnections[message.from] else {
      logger.warning("no peer connection for \(message.from)")
      return
    }

    guard case .answer(let sdpString) = message.payload else {
      logger.error("payload is not .answer")
      return
    }
    let remoteSdp = RTCSessionDescription(type: .answer, sdp: sdpString)

    do {
      try await pc.setRemoteDescription(remoteSdp)
      await drainCandidateQueue(for: message.from)
      logger.info("remote description set for \(message.from)")
    } catch {
      logger.error("setRemoteDescription failed: \(error.localizedDescription)")
    }
  }

  private func handleCandidate(_ message: SignalMessage) async {
    guard let pc = peerConnections[message.from] else {
      logger.warning("no peer connection for \(message.from)")
      return
    }

    guard case .candidate(let sdpString, let sdpMid, let sdpMLineIndex) = message.payload else {
      logger.error("payload is not .candidate")
      return
    }
    let candidate = RTCIceCandidate(sdp: sdpString, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)

    if pc.remoteDescription != nil {
      do {
        try await pc.add(candidate)
        logger.info("candidate added for \(message.from)")
      } catch {
        logger.error("add failed: \(error.localizedDescription)")
      }
    } else {
      if candidateQueues[message.from] == nil {
        candidateQueues[message.from] = []
      }
      candidateQueues[message.from]?.append(candidate)
      logger.info("queued candidate for \(message.from) (queue size: \(candidateQueues[message.from]?.count ?? 0))")
    }
  }

  private func handleConnectionRequest(_ message: SignalMessage) async {
    if isDuplicate(message.from, sequence: message.sequence) {
      logger.debug("ignoring duplicate sequence from \(message.from)")
      return
    }

    logger.info("\(message.from) is asking us to initiate")
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
        logger.error("add failed for \(peer)")
      }
    }
    logger.info("drained \(queued.count) candidates for \(peer)")
  }

  private func closePeerConnection(_ peer: String, resetReconnectState: Bool = true) {
    clearConnectionTimeout(for: peer)
    if resetReconnectState {
      reconnectTasks[peer]?.cancel()
      reconnectTasks[peer] = nil
      reconnectAttempts[peer] = nil
    }
    dataChannels[peer]?.close()
    dataChannels[peer] = nil
    peerConnections[peer]?.close()
    peerConnections[peer] = nil
    candidateQueues[peer] = nil
    connectionLocks.remove(peer)
    connectedPeers.remove(peer)
  }

  private func startConnectionTimeout(for peer: String) {
    connectionTimeouts[peer]?.cancel()
    connectionTimeouts[peer] = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(Self.connectionTimeout * 1_000_000_000))

      guard let self else { return }
      if Task.isCancelled { return }
      self.connectionTimeouts[peer] = nil

      // Check if we already connected then don't do anything
      if self.connectedPeers.contains(peer) { return }

      self.logger.warning("connectionTimeout: \(peer) did not reach connected in \(Self.connectionTimeout)s, treating as failure")
      self.scheduleReconnect(to: peer)
    }
  }

  private func clearConnectionTimeout(for peer: String) {
    connectionTimeouts[peer]?.cancel()
    connectionTimeouts[peer] = nil
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

  // Glare resolution: the lexicographically smaller username is the caller.
  // Plain `<` is byte/code-unit comparison — locale-independent, so iOS and web
  // agree on roles regardless of either device's system locale.
  private func shouldInitiateConnection(to peer: String) -> Bool {
    return userService.user < peer
  }

  private func peer(forConnectionID id: ObjectIdentifier) -> String? {
    peerConnections.first { ObjectIdentifier($0.value) == id }?.key
  }

  private func peer(forChannelID id: ObjectIdentifier) -> String? {
    dataChannels.first { ObjectIdentifier($0.value) == id }?.key
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
        self.logger.warning("unknown peer connection")
        return
      }

      let candidateMessage = SignalMessage(
        payload: .candidate(sdp: sdp, sdpMid: sdpMid, sdpMLineIndex: sdpMLineIndex),
        from: self.userService.user,
        to: peer,
        sequence: self.nextSequence(for: peer),
      )
      await self.wsService.sendSignal(candidateMessage)
    }
  }

  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
    let peerConnectionID = ObjectIdentifier(peerConnection)
    let box = UnsafeSendable(value: dataChannel)

    Task { @MainActor [weak self] in
      guard let self else { return }

      guard let peer = self.peer(forConnectionID: peerConnectionID) else {
        self.logger.warning("unknown peer connection")
        return
      }

      box.value.delegate = self
      self.dataChannels[peer] = box.value
      self.logger.info("data channel attached to peer: \(peer)")
    }
  }

  nonisolated func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
    let dataChannelID = ObjectIdentifier(dataChannel)
    let state = dataChannel.readyState

    Task { @MainActor [weak self] in
      guard let self else { return }

      guard let peer = self.peer(forChannelID: dataChannelID) else {
        self.logger.debug("unknown channel (already closed)")
        return
      }

      switch state {
      case .open:
        self.connectedPeers.insert(peer)
        self.connectionLocks.remove(peer)
        self.reconnectAttempts[peer] = nil
        self.clearConnectionTimeout(for: peer)
        self.logger.info("connected to \(peer)")
      case .closed:
        self.connectedPeers.remove(peer)
        self.connectionLocks.remove(peer)
        self.logger.info("disconnected from \(peer)")
        self.scheduleReconnect(to: peer)
      case .connecting:
        self.logger.info("connecting to \(peer)")
      case .closing:
        self.logger.info("closing connection to \(peer)")
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
        self.logger.warning("unknown channel")
        return
      }

      if isBinary {
        self.logger.info("received \(bytes.count) bytes from \(peer)")
      } else {
        guard let text = String(bytes: bytes, encoding: .utf8) else {
          self.logger.warning("non-UTF-8 bytes from \(peer)")
          return
        }
        self.logger.info("received from \(peer): \(text)")
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
