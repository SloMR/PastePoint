//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Combine
import Foundation
import WebRTC

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

  @Published var connectedPeers: Set<String> = []
  @Published var connectingPeers: Set<String> = []

  var reachablePeers: Set<String> {
    connectedPeers.union(connectingPeers)
  }

  let bufferedAmountLow = PassthroughSubject<String, Never>()
  /// A peer we have given up on while it is still in the room. Nothing queued for
  /// it will ever be delivered, so transfers waiting on it have to be failed.
  let peerUnreachable = PassthroughSubject<String, Never>()
  let chatMessages = PassthroughSubject<ChatMessage, Never>()
  let fileEvent = PassthroughSubject<FileChannelEvent, Never>()
  let chunkReceived = PassthroughSubject<(ParsedChunk, from: String), Never>()

  let wsService: any SignalTransport
  let userService: UserService
  let peerDirectory: PeerDirectory
  let blockService: BlockService
  let turnCredentials: any IceServerSource
  let webRTC: any WebRTCEngine
  let clock: any Clock<Duration>
  private var cancellables: Set<AnyCancellable> = []

  static let connectionTimeout: TimeInterval = 8.0 // Seconds
  static let connectionCeiling: TimeInterval = 30.0 // Seconds
  static let connectionRequestTimeout: TimeInterval = 15.0 // Seconds
  static let maxReconnectAttempts = 5
  static let baseReconnectDelay: TimeInterval = 2.0 // Seconds
  static let maxReconnectDelay: TimeInterval = 10.0 // Seconds
  static let maxPendingMessages = 64
  static let maxQueuedCandidates = 128
  static let connectSpanAbandonAfter: TimeInterval = 120.0 // Seconds

  var peerConnections: [String: RTCPeerConnection] = [:]
  var dataChannels: [String: RTCDataChannel] = [:]
  var candidateQueues: [String: [RTCIceCandidate]] = [:]
  var describedConnections: Set<ObjectIdentifier> = []
  var collectedCandidates: [String: [String]] = [:]
  var connectionLocks: Set<String> = []

  var reconnectAttempts: [String: Int] = [:]
  var reconnectTasks: [String: Task<Void, Never>] = [:]
  var connectionTimeouts: [String: Task<Void, Never>] = [:]
  var connectionRequestTimeouts: [String: Task<Void, Never>] = [:]
  private var pendingOpens: Set<String> = []
  var pendingMessages: [String: [Data]] = [:]

  var connectSpans: [String: TelemetrySpan] = [:]
  var connectAttemptCounts: [String: Int] = [:]
  var connectSpanAbandonTasks: [String: Task<Void, Never>] = [:]

  // MARK: - Init

  init(
    wsService: any SignalTransport,
    userService: UserService,
    peerDirectory: PeerDirectory,
    blockService: BlockService,
    turnCredentials: any IceServerSource = TurnCredentialsService(),
    webRTC: any WebRTCEngine = DefaultWebRTCEngine(),
    clock: any Clock<Duration> = SuspendingClock(),
  ) {
    self.wsService = wsService
    self.userService = userService
    self.peerDirectory = peerDirectory
    self.blockService = blockService
    self.turnCredentials = turnCredentials
    self.webRTC = webRTC
    self.clock = clock
    super.init()

    wsService.signalMessage
      .receive(on: DispatchQueue.main)
      .sink { [weak self] message in
        self?.handle(message)
      }
      .store(in: &cancellables)

    // Warm the TURN credential cache on connect so the first peer connection
    wsService.didConnect
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in
        Task { _ = await self?.turnCredentials.iceServers() }
      }
      .store(in: &cancellables)

    peerDirectory.$peers
      .receive(on: DispatchQueue.main)
      .sink { [weak self] peers in
        self?.syncMesh(peers: peers)
      }
      .store(in: &cancellables)
  }

  // MARK: - Public API

  func initiateConnection(to peer: String, force: Bool = false) async {
    if connectSpans[peer] == nil {
      startConnectSpan(for: peer)
    }
    guard !isAlreadyHandled(peer, force: force) else { return }

    await userService.waitForUsername()
    // The role can only be known once we have a name.
    telemetry.setAttributes(["role": connectRole(for: peer)], on: connectSpans[peer])

    // The guards above ran before that suspension; another caller may have
    // started an attempt for this peer while we waited.
    guard !connectionLocks.contains(peer), peerConnections[peer] == nil else {
      log.debug("attempt for \(peer) already started while waiting for a username")
      return
    }

    if !force, !shouldInitiateConnection(to: peer) {
      log.info("not the designated caller, sending connection request")
      let request = SignalMessage(
        payload: .connectionRequest,
        from: userService.user,
        to: peer,
      )
      await wsService.sendSignal(request)
      connectingPeers.insert(peer)
      recordConnectAttempt(peer)
      // If the designated caller never re-offers, take over and initiate ourselves
      startConnectionRequestTimeout(for: peer)
      return
    }

    connectionLocks.insert(peer)
    connectingPeers.insert(peer)
    cancelScheduledReconnect(for: peer)
    recordConnectAttempt(peer)
    startConnectionTimeout(for: peer)

    let iceServers = await turnCredentials.iceServers()

    // Another path may have taken over while we waited; it owns the lock now,
    // so leave it alone and let its connection stand.
    guard peerConnections[peer] == nil else {
      log.debug("connection to \(peer) appeared while waiting for credentials")
      return
    }

    guard let pc = await makeCallerConnection(for: peer, iceServers: iceServers) else { return }

    let offerSdp: String
    do {
      offerSdp = try await webRTC.makeLocalDescription(.offer, on: pc)
    } catch {
      guard peerConnections[peer] === pc else {
        log.debug("offer for \(peer) superseded during SDP setup")
        return
      }
      log.error("SDP offer failed: \(error.localizedDescription)")
      webRTC.close(peerConnections.removeValue(forKey: peer), channel: dataChannels.removeValue(forKey: peer))
      connectionLocks.remove(peer)
      return
    }
    guard peerConnections[peer] === pc else { return }

    let offerMessage = SignalMessage(
      payload: .offer(sdp: offerSdp),
      from: userService.user,
      to: peer,
    )
    await wsService.sendSignal(offerMessage)
    telemetry.markElapsed("webrtc.offer_sent_ms", on: connectSpans[peer])
    log.info("offer sent")
  }

  /// Creates and registers the caller's connection and data channel; nil if the attempt ended meanwhile.
  private func makeCallerConnection(for peer: String, iceServers: [RTCIceServer]) async -> RTCPeerConnection? {
    guard let pc = await webRTC.makePeerConnection(iceServers: iceServers, delegate: self) else {
      log.error("factory returned nil")
      connectionLocks.remove(peer)
      return nil
    }
    let channel = await webRTC.makeDataChannel(on: pc, label: "data")

    // Same check after these suspensions; a teardown in between also released the lock.
    guard peerConnections[peer] == nil, connectionLocks.contains(peer) else {
      log.debug("attempt for \(peer) superseded while creating its connection")
      webRTC.close(pc, channel: channel)
      return nil
    }
    peerConnections[peer] = pc
    telemetry.markElapsed("webrtc.pc_created_ms", on: connectSpans[peer])

    guard let channel else {
      log.error("failed to create data channel")
      webRTC.close(peerConnections.removeValue(forKey: peer), channel: nil)
      connectionLocks.remove(peer)
      return nil
    }
    channel.delegate = self
    dataChannels[peer] = channel
    return pc
  }

  /// The guards that run before the first suspension; ends the span as skipped where web does.
  private func isAlreadyHandled(_ peer: String, force: Bool) -> Bool {
    if connectionLocks.contains(peer) {
      log.debug("already locked for \(peer)")
      return true
    }

    if let existing = peerConnections[peer] {
      log.warning("already have a connection to this peer")
      if !force {
        finishConnectSpanAsSkipped(peer, existing: existing)
      }
      return true
    }

    if !force, connectionRequestTimeouts[peer] != nil {
      log.debug("connection request already outstanding for \(peer)")
      return true
    }
    return false
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
      log.info("closing connection to peer (left room)")
      finishConnectSpan(peer, ok: false, outcome: .cancelled)
      closePeerConnection(peer)
    }

    for peer in toOpen {
      log.info("opening connection to peer (joined room)")
      pendingOpens.insert(peer)
      Task {
        await initiateConnection(to: peer)
        pendingOpens.remove(peer)
      }
    }
  }
}

// MARK: - Helpers

extension SignalingService {

  // Glare resolution: the lexicographically smaller username is the caller.
  // Plain `<` is byte/code-unit comparison — locale-independent, so iOS and web
  // agree on roles regardless of either device's system locale.
  func shouldInitiateConnection(to peer: String) -> Bool {
    return userService.user < peer
  }

  func peer(forConnectionID id: ObjectIdentifier) -> String? {
    peerConnections.first { ObjectIdentifier($0.value) == id }?.key
  }

  func peer(forChannelID id: ObjectIdentifier) -> String? {
    dataChannels.first { ObjectIdentifier($0.value) == id }?.key
  }
}
