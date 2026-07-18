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

enum FileChannelEvent {
  case offer(FileOfferPayload, from: String)
  case accept(FileAcceptPayload, from: String)
  case decline(FileDeclinePayload, from: String)
  case cancelUpload(FileCancelPayload, from: String)
  case cancelDownload(FileCancelPayload, from: String)
  case received(FileReceivedPayload, from: String)
}

@MainActor
final class SignalingService: NSObject, ObservableObject {

  @Published private(set) var connectedPeers: Set<String> = []
  @Published private(set) var connectingPeers: Set<String> = []

  let bufferedAmountLow = PassthroughSubject<String, Never>()
  let chatMessages = PassthroughSubject<ChatMessage, Never>()
  let fileEvent = PassthroughSubject<FileChannelEvent, Never>()
  let chunkReceived = PassthroughSubject<(ParsedChunk, from: String), Never>()

  private let logger = Logger(label: "SignalingService")
  private let wsService: WebSocketConnectionService
  private let userService: UserService
  private let peerDirectory: PeerDirectory
  private let blockService: BlockService
  private var cancellables: Set<AnyCancellable> = []

  private static let connectionTimeout: TimeInterval = 8.0 // Seconds
  private static let connectionRequestTimeout: TimeInterval = 15.0 // Seconds
  private static let maxReconnectAttempts = 5
  private static let baseReconnectDelay: TimeInterval = 2.0 // Seconds
  private static let maxReconnectDelay: TimeInterval = 10.0 // Seconds

  private var peerConnections: [String: RTCPeerConnection] = [:]
  private var dataChannels: [String: RTCDataChannel] = [:]
  private var candidateQueues: [String: [RTCIceCandidate]] = [:]
  private var collectedCandidates: [String: [String]] = [:]
  private var connectionLocks: Set<String> = []
  private var outboundSequences: [String: Int] = [:]
  private var inboundSequences: [String: Int] = [:]

  private var reconnectAttempts: [String: Int] = [:]
  private var reconnectTasks: [String: Task<Void, Never>] = [:]
  private var connectionTimeouts: [String: Task<Void, Never>] = [:]
  private var connectionRequestTimeouts: [String: Task<Void, Never>] = [:]
  private var pendingOpens: Set<String> = []

  // MARK: - Init

  init(
    wsService: WebSocketConnectionService,
    userService: UserService,
    peerDirectory: PeerDirectory,
    blockService: BlockService,
  ) {
    self.wsService = wsService
    self.userService = userService
    self.peerDirectory = peerDirectory
    self.blockService = blockService
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

    wsService.didReconnect
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in
        Task { @MainActor in
          await self?.userService.waitForUsername()
          self?.resetMesh()
        }
      }
      .store(in: &cancellables)
  }

  // MARK: - Public API

  func initiateConnection(to peer: String, force: Bool = false) async {
    guard !connectionLocks.contains(peer) else {
      logger.debug("already locked for \(peer)")
      return
    }

    guard peerConnections[peer] == nil else {
      logger.warning("already have a connection to \(peer)")
      return
    }

    if !force, connectionRequestTimeouts[peer] != nil {
      logger.debug("connection request already outstanding for \(peer)")
      return
    }

    await userService.waitForUsername()
    if !force, !shouldInitiateConnection(to: peer) {
      logger.info("not the designated caller for \(peer), sending connection request")
      let request = SignalMessage(
        payload: .connectionRequest,
        from: userService.user,
        to: peer,
        sequence: nextSequence(for: peer),
      )
      await wsService.sendSignal(request)
      connectingPeers.insert(peer)
      // If the designated caller never re-offers, take over and initiate ourselves
      startConnectionRequestTimeout(for: peer)
      return
    }

    connectionLocks.insert(peer)
    connectingPeers.insert(peer)
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

  func isReadyToSend(to peer: String) -> Bool {
    guard let channel = dataChannels[peer], channel.readyState == .open else {
      return false
    }

    return channel.bufferedAmount < WebRTCConfig.maxBufferedAmount
  }

  // MARK: - Mesh Sync

  private func syncMesh(peers: [String]) {
#if DEBUG
    guard !AppBuildInfo.isXcodePreview else { return }
#endif

    let target = Set(peers)
    let tracked = Set(peerConnections.keys)
      .union(connectionLocks)
      .union(connectionRequestTimeouts.keys)
      .union(pendingOpens)

    let toOpen = target.subtracting(tracked)
    let toClose = tracked.subtracting(target)

    for peer in toClose {
      logger.info("closing connection to \(peer) (left room)")
      closePeerConnection(peer)
    }

    for peer in toOpen {
      logger.info("opening connection to \(peer) (joined room)")
      pendingOpens.insert(peer)
      Task {
        await initiateConnection(to: peer)
        pendingOpens.remove(peer)
      }
    }
  }

  private func resetMesh() {
    for peer in Set(peerConnections.keys).union(connectionLocks) {
      closePeerConnection(peer)
    }
    pendingOpens.removeAll()

    syncMesh(peers: peerDirectory.peers)
  }
}

// MARK: - Inbound Signal Handling

extension SignalingService {

  private func handle(_ message: SignalMessage) {
    guard !message.from.isEmpty else {
      logger.warning("ignoring message with empty 'from'")
      return
    }

    guard !blockService.isBlocked(message.from) else {
      logger.info("ignoring \(message.payload.typeString) from blocked peer \(message.from)")
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

  private func handleOffer(_ message: SignalMessage) async {
    await userService.waitForUsername()

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
    connectingPeers.insert(message.from)
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
    guard case .candidate(let sdpString, let sdpMid, let sdpMLineIndex) = message.payload else {
      logger.error("payload is not .candidate")
      return
    }
    let candidate = RTCIceCandidate(sdp: sdpString, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)

    guard let pc = peerConnections[message.from], pc.remoteDescription != nil else {
      candidateQueues[message.from, default: []].append(candidate)
      logger.info("queued candidate for \(message.from) (queue size: \(candidateQueues[message.from]?.count ?? 0))")
      return
    }

    do {
      try await pc.add(candidate)
      logger.info("candidate added for \(message.from)")
    } catch {
      logger.error("add failed: \(error.localizedDescription)")
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
}

// MARK: - Reconnect

extension SignalingService {

  private func scheduleReconnect(to peer: String) {
    guard reconnectTasks[peer] == nil else {
      logger.debug("already scheduled for \(peer)")
      return
    }

    // Only connect if the peer is still expected to be in the room
    guard peerDirectory.peers.contains(peer) else {
      logger.info("\(peer) is no longer a peer, skipping")
      reconnectAttempts[peer] = nil
      connectingPeers.remove(peer)
      return
    }

    let attempts = reconnectAttempts[peer] ?? 0
    guard attempts < Self.maxReconnectAttempts else {
      logger.error("max attempts reached for \(peer)")
      reconnectAttempts[peer] = nil
      connectingPeers.remove(peer)
      return
    }

    reconnectAttempts[peer] = attempts + 1
    connectingPeers.insert(peer)

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
        connectingPeers.remove(peer)
        return
      }

      // Don't reconnect if we have already healed since scheduling
      if self.connectedPeers.contains(peer) {
        self.logger.debug("\(peer) already healthy, skipping")
        self.reconnectAttempts[peer] = nil
        connectingPeers.remove(peer)
        return
      }

      self.logger.info("reconnecting to \(peer)")
      self.closePeerConnection(peer, resetReconnectState: false)
      await self.initiateConnection(to: peer)
    }

  }

  private func startConnectionTimeout(for peer: String) {
    connectionRequestTimeouts[peer]?.cancel()
    connectionRequestTimeouts[peer] = nil
    connectionTimeouts[peer]?.cancel()
    connectionTimeouts[peer] = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(Self.connectionTimeout * 1_000_000_000))

      guard let self else { return }
      if Task.isCancelled { return }
      self.connectionTimeouts[peer] = nil

      // Check if we already connected then don't do anything
      if self.connectedPeers.contains(peer) { return }

      self.logger.warning("connectionTimeout: \(peer) did not reach connected in \(Self.connectionTimeout)s, treating as failure")
      self.logConnectionDiagnostics(for: peer)
      self.scheduleReconnect(to: peer)
    }
  }

  private func clearConnectionTimeout(for peer: String) {
    connectionTimeouts[peer]?.cancel()
    connectionTimeouts[peer] = nil
  }

  /// Watchdog for the non-caller: if the designated caller never re-offers within
  /// `connectionRequestTimeout`, force-initiate ourselves.
  /// Superseded by `startConnectionTimeout` once a real
  /// peer connection attempt begins; cleared in `closePeerConnection`.
  private func startConnectionRequestTimeout(for peer: String) {
    connectionRequestTimeouts[peer]?.cancel()
    connectionRequestTimeouts[peer] = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(Self.connectionRequestTimeout * 1_000_000_000))

      guard !Task.isCancelled, let self else { return }
      self.connectionRequestTimeouts[peer] = nil

      guard self.peerConnections[peer] == nil, self.peerDirectory.peers.contains(peer) else { return }
      self.logger.warning("no offer from \(peer) within \(Self.connectionRequestTimeout)s — force-initiating")
      await self.initiateConnection(to: peer, force: true)
    }
  }

  private func closePeerConnection(_ peer: String, resetReconnectState: Bool = true) {
    clearConnectionTimeout(for: peer)
    connectionRequestTimeouts[peer]?.cancel()
    connectionRequestTimeouts[peer] = nil
    if resetReconnectState {
      reconnectTasks[peer]?.cancel()
      reconnectTasks[peer] = nil
      reconnectAttempts[peer] = nil
      outboundSequences[peer] = nil
      inboundSequences[peer] = nil
    }

    let dataChannel = dataChannels.removeValue(forKey: peer)
    let peerConnection = peerConnections.removeValue(forKey: peer)
    if dataChannel != nil || peerConnection != nil {
      let closing = UnsafeSendable(value: (dataChannel, peerConnection))
      Task.detached {
        closing.value.0?.close()
        closing.value.1?.close()
      }
    }

    candidateQueues[peer] = nil
    collectedCandidates[peer] = nil
    connectionLocks.remove(peer)
    connectedPeers.remove(peer)
    connectingPeers.remove(peer)
  }

  // MARK: - Diagnostics

  /// Extracts the ICE candidate type (`host` / `srflx` / `relay` / `prflx`) from
  /// a candidate SDP line, which carries a `typ <type>` token.
  private func candidateType(from sdp: String) -> String {
    let parts = sdp.split(separator: " ")
    if let i = parts.firstIndex(of: "typ"), i + 1 < parts.count {
      return String(parts[i + 1])
    }
    return "unknown"
  }

  private func logConnectionDiagnostics(for peer: String) {
    guard let pc = peerConnections[peer] else { return }
    let candidates = collectedCandidates[peer] ?? []
    let hasRelay = candidates.contains("relay")
    let hasSrflx = candidates.contains("srflx")

    var report = "Connection FAILED with \(peer):\n"
    report += "  State: \(pc.connectionState.rawValue) / ICE: \(pc.iceConnectionState.rawValue)\n"
    report += "  Candidates: \(candidates.count) total (relay: \(hasRelay ? "✓" : "✗"), srflx: \(hasSrflx ? "✓" : "✗"))"
    if !hasRelay {
      report += "\n  ISSUE: No TURN relay candidates — connection will fail behind symmetric NAT"
    }
    logger.error("\(report)")
  }
}

// MARK: - Data Channel Send

extension SignalingService {

  /// Send a chat message to every open data channel.
  /// Returns the list of peers it actually reached.
  @discardableResult
  func broadcastChat(_ message: ChatMessage) -> [String] {
#if DEBUG
    if AppBuildInfo.isXcodePreview {
      return peerDirectory.peers
    }
#endif

    guard let data = encodeChatForWire(message) else { return [] }

    let openPeers = dataChannels
      .filter { $0.value.readyState == .open }
      .map { $0.key }

    return openPeers.filter {
      send(data, to: $0)
    }
  }

  /// Transport hook: send a pre-encoded data-channel envelope to one peer.
  /// Returns false if the channel is closed or back-pressured.
  /// Called by services that build their own envelopes (e.g. `FileTransferService`).
  func send(_ data: Data, to peer: String, isBinary: Bool = false) -> Bool {
    guard let channel = dataChannels[peer], channel.readyState == .open else {
      logger.warning("no open channel to \(peer)")
      return false
    }

    guard channel.bufferedAmount < WebRTCConfig.maxBufferedAmount else {
      logger.warning("channel to \(peer) back-pressured (\(channel.bufferedAmount) bytes)")
      return false
    }

    return channel.sendData(RTCDataBuffer(data: data, isBinary: isBinary))
  }

  private func encodeChatForWire(_ chat: ChatMessage) -> Data? {
    do {
      return try DataChannelMessage.encodeChat(chat)
    } catch {
      logger.error("encodeChat failed: \(error)")
      return nil
    }
  }
}

// MARK: - Helpers

extension SignalingService {

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

// MARK: - RTCPeerConnectionDelegate

extension SignalingService: RTCPeerConnectionDelegate {

  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
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

  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
    let peerConnectionID = ObjectIdentifier(peerConnection)
    let sdp = candidate.sdp
    let sdpMid = candidate.sdpMid
    let sdpMLineIndex = candidate.sdpMLineIndex

    Task { @MainActor [weak self] in
      guard let self else { return }
      await userService.waitForUsername()

      guard let peer = self.peer(forConnectionID: peerConnectionID) else {
        self.logger.warning("unknown peer connection")
        return
      }

      self.collectedCandidates[peer, default: []].append(self.candidateType(from: sdp))

      let candidateMessage = SignalMessage(
        payload: .candidate(sdp: sdp, sdpMid: sdpMid, sdpMLineIndex: sdpMLineIndex),
        from: self.userService.user,
        to: peer,
        sequence: self.nextSequence(for: peer),
      )
      await self.wsService.sendSignal(candidateMessage)
    }
  }

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
      if box.value.readyState == .open {
        self.handleChannelOpened(peer)
      }
    }
  }
}

// MARK: - RTCDataChannelDelegate

extension SignalingService: RTCDataChannelDelegate {

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
        handleChannelOpened(peer)
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

  private func handleChannelOpened(_ peer: String) {
    guard !connectedPeers.contains(peer) else { return }
    connectedPeers.insert(peer)
    connectingPeers.remove(peer)
    connectionLocks.remove(peer)
    reconnectAttempts[peer] = nil
    clearConnectionTimeout(for: peer)
    self.logger.info("connected to \(peer)")
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
        guard let parsed = BinaryChunk.decode(bytes) else {
          self.logger.warning("dropped malformed binary chunk from \(peer)")
          return
        }

        self.chunkReceived.send((parsed, from: peer))
        return
      }

      do {
        let decoded = try DataChannelMessage.decode(bytes)
        self.route(decoded, from: peer)
      } catch {
        self.logger.error("failed to decode data-channel message from \(peer): \(error)")
      }
    }
  }

  private func route(_ decoded: DataChannelMessage.Decoded, from peer: String) {
    guard !blockService.isBlocked(peer) else {
      logger.info("dropping data-channel message from blocked peer \(peer)")
      return
    }

    switch decoded {
    case .chat(let msg): chatMessages.send(msg)
    case .fileOffer(let payload): fileEvent.send(.offer(payload, from: peer))
    case .fileAccept(let payload): fileEvent.send(.accept(payload, from: peer))
    case .fileDecline(let payload): fileEvent.send(.decline(payload, from: peer))
    case .fileCancelUpload(let payload): fileEvent.send(.cancelUpload(payload, from: peer))
    case .fileCancelDownload(let payload): fileEvent.send(.cancelDownload(payload, from: peer))
    case .fileReceived(let payload): fileEvent.send(.received(payload, from: peer))
    case .unknown(let type): logger.warning("unknown data-channel type \(type) from \(peer)")
    }
  }

  nonisolated func dataChannel(_ dataChannel: RTCDataChannel, didChangeBufferedAmount amount: UInt64) {
    let dataChannelID = ObjectIdentifier(dataChannel)
    let currentBuffered = dataChannel.bufferedAmount

    Task { @MainActor [weak self] in
      guard let self else { return }
      guard let peer = self.peer(forChannelID: dataChannelID) else { return }

      if currentBuffered < WebRTCConfig.bufferedAmountLowThreshold {
        self.bufferedAmountLow.send(peer)
      }
    }
  }
}
