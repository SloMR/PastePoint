//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation
import WebRTC

// MARK: - Inbound Signal Handling

extension SignalingService {

  func handle(_ message: SignalMessage) {
    guard !message.from.isEmpty else {
      log.warning("ignoring message with empty 'from'")
      return
    }

    guard !blockService.isBlocked(message.from) else {
      log.info("ignoring \(message.payload.typeString) from blocked peer")
      return
    }

    log.debug("received \(message.payload.typeString) from \(message.from)")
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

    if connectionLocks.contains(message.from) {
      log.warning("offer collision, resolving by role")
      if shouldInitiateConnection(to: message.from) {
        log.debug("ignoring offer from \(message.from) (we are the designated caller)")
        return
      } else {
        log.debug("canceling our initiation for \(message.from) (we are the designated callee)")
        closePeerConnection(message.from, resetReconnectState: false)
      }
    } else if peerConnections[message.from] != nil {
      log.debug("replacing the connection to \(message.from) with its new offer")
      closePeerConnection(message.from, resetReconnectState: false)
    }

    connectionLocks.insert(message.from)
    connectingPeers.insert(message.from)
    cancelScheduledReconnect(for: message.from)
    startConnectionTimeout(for: message.from)

    guard case .offer(let sdpString) = message.payload else {
      log.error("payload is not .offer (received \(message.payload.typeString))")
      return
    }

    let iceServers = await turnCredentials.iceServers()
    guard let pc = await webRTC.makePeerConnection(iceServers: iceServers, delegate: self) else {
      log.error("factory returned nil")
      connectionLocks.remove(message.from)
      return
    }

    // A teardown while the connection was being created released the lock.
    guard connectionLocks.contains(message.from) else {
      log.debug("offer from \(message.from) superseded while creating its connection")
      webRTC.close(pc, channel: nil)
      return
    }
    if let replaced = peerConnections.updateValue(pc, forKey: message.from) {
      describedConnections.remove(ObjectIdentifier(replaced))
      webRTC.close(replaced, channel: nil)
    }
    telemetry.markElapsed("webrtc.pc_created_ms", on: connectSpans[message.from])

    let answerSdp: String
    do {
      try await webRTC.setRemoteDescription(.offer, sdp: sdpString, on: pc)
      markRemoteDescriptionSet(on: pc, for: message.from)
      await drainCandidateQueue(for: message.from)
      answerSdp = try await webRTC.makeLocalDescription(.answer, on: pc)
    } catch {
      guard peerConnections[message.from] === pc else {
        log.debug("answer for \(message.from) superseded during SDP setup")
        return
      }
      log.error("SDP exchange failed: \(error.localizedDescription)")
      peerConnections[message.from] = nil
      describedConnections.remove(ObjectIdentifier(pc))
      webRTC.close(pc, channel: nil)
      connectionLocks.remove(message.from)
      return
    }
    guard peerConnections[message.from] === pc else { return }

    let response = SignalMessage(
      payload: .answer(sdp: answerSdp),
      from: userService.user,
      to: message.from,
    )
    await wsService.sendSignal(response)
    telemetry.markElapsed("webrtc.answer_sent_ms", on: connectSpans[message.from])
    log.info("answer sent")
  }

  private func handleAnswer(_ message: SignalMessage) async {
    guard let pc = peerConnections[message.from] else {
      log.warning("no peer connection for this peer")
      return
    }

    guard case .answer(let sdpString) = message.payload else {
      log.error("payload is not .answer")
      return
    }

    do {
      try await webRTC.setRemoteDescription(.answer, sdp: sdpString, on: pc)
      markRemoteDescriptionSet(on: pc, for: message.from)
      await drainCandidateQueue(for: message.from)
      log.info("remote description set")
    } catch {
      guard peerConnections[message.from] === pc else {
        log.debug("answer from \(message.from) arrived after teardown")
        return
      }
      log.error("setRemoteDescription failed: \(error.localizedDescription)")
    }
  }

  private func handleCandidate(_ message: SignalMessage) async {
    guard case .candidate(let sdpString, let sdpMid, let sdpMLineIndex) = message.payload else {
      log.error("payload is not .candidate")
      return
    }
    let candidate = RTCIceCandidate(sdp: sdpString, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)

    guard let pc = peerConnections[message.from], describedConnections.contains(ObjectIdentifier(pc)) else {
      guard candidateQueues[message.from, default: []].count < Self.maxQueuedCandidates else {
        log.warning("dropping ICE candidate: queue is full")
        return
      }
      candidateQueues[message.from, default: []].append(candidate)
      log.debug("queued candidate for \(message.from) (queue size: \(candidateQueues[message.from]?.count ?? 0))")
      return
    }

    do {
      try await webRTC.add(candidate, to: pc)
      log.debug("candidate added for \(message.from)")
    } catch {
      guard peerConnections[message.from] === pc else {
        log.debug("candidate from \(message.from) arrived after teardown")
        return
      }
      log.warning("add failed: \(error.localizedDescription)")
    }
  }

  private func handleConnectionRequest(_ message: SignalMessage) async {
    log.info("peer is asking us to initiate")
    await initiateConnection(to: message.from)
  }

  /// Lets candidates go straight to `pc` from now on, unless it was replaced while the description applied.
  private func markRemoteDescriptionSet(on pc: RTCPeerConnection, for peer: String) {
    guard peerConnections[peer] === pc else { return }
    describedConnections.insert(ObjectIdentifier(pc))
    telemetry.markElapsed("webrtc.remote_sdp_ms", on: connectSpans[peer])
  }

  private func drainCandidateQueue(for peer: String) async {
    guard let pc = peerConnections[peer] else { return }
    guard let queued = candidateQueues[peer], !queued.isEmpty else { return }

    candidateQueues[peer] = nil

    for candidate in queued {
      do {
        try await webRTC.add(candidate, to: pc)
      } catch {
        log.warning("queued candidate add failed")
      }
    }
    log.info("drained \(queued.count) candidates")
  }
}
