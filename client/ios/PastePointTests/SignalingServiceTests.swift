//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Clocks
import Combine
import Foundation
import Testing
@preconcurrency import WebRTC
@testable import PastePoint

@MainActor
struct SignalingServiceTests {
  @Test("After a connection fails to build, the peer isn't left connecting")
  func failedBuildDoesNotLeavePeerConnecting() async {
    let fixture = await SignalingFixture()
    fixture.webRTC.failsToConnect = true

    fixture.setPeers(["bob"])
    #expect(await fixture.waitUntil { fixture.signaling.connectingPeers.contains("bob") })

    await fixture.clock.advance(by: .seconds(120))

    #expect(await fixture.waitUntil { !fixture.signaling.connectingPeers.contains("bob") })
  }

  @Test("After the retry budget runs out, no queued frame survives")
  func givingUpDropsQueuedFrames() async {
    let fixture = await SignalingFixture()
    fixture.webRTC.failsToConnect = true
    fixture.setPeers(["bob"])
    #expect(await fixture.waitUntil { fixture.signaling.connectingPeers.contains("bob") })

    #expect(fixture.signaling.send(Data("one".utf8), to: "bob"))
    #expect(fixture.signaling.send(Data("two".utf8), to: "bob"))

    await fixture.clock.advance(by: .seconds(30))
    #expect(fixture.signaling.pendingMessages["bob"]?.count == 2)

    await fixture.clock.advance(by: .seconds(90))
    #expect(await fixture.waitUntil { fixture.signaling.pendingMessages["bob"] == nil })
    #expect(fixture.webRTC.sentFrames.isEmpty)
  }

  @Test("A frame sent after the channel opens arrives after the frames queued before it")
  func framesKeepTheirOrderWhenTheChannelOpens() async throws {
    let fixture = await SignalingFixture()
    fixture.setPeers(["bob"])
    #expect(await fixture.waitUntil { fixture.transport.sent.count == 1 })
    let channel = try #require(fixture.signaling.dataChannels["bob"])

    #expect(fixture.signaling.send(Data("one".utf8), to: "bob"))
    #expect(fixture.signaling.send(Data("two".utf8), to: "bob"))

    fixture.signaling.handleChannelState(.open, onChannel: ObjectIdentifier(channel))
    #expect(fixture.signaling.send(Data("three".utf8), to: "bob"))

    #expect(await fixture.waitUntil { fixture.webRTC.sentFrames.count == 3 })
    #expect(fixture.webRTC.sentFrames == ["one", "two", "three"].map { Data($0.utf8) })
  }

  @Test("A teardown followed by a new attempt never leaves two live connections")
  func teardownThenNewAttemptLeavesOneConnection() async {
    let fixture = await SignalingFixture()
    fixture.webRTC.pauseNewConnections()
    fixture.setPeers(["bob"])
    #expect(await fixture.waitUntil { fixture.webRTC.pausedConnections == 1 })

    fixture.setPeers([])
    #expect(await fixture.waitUntil { !fixture.signaling.connectionLocks.contains("bob") })

    fixture.transport.signalMessage.send(SignalMessage(payload: .connectionRequest, from: "bob", to: fixture.me))
    #expect(await fixture.waitUntil { fixture.webRTC.pausedConnections == 2 })

    fixture.webRTC.resumeNewConnections()
    #expect(await fixture.waitUntil { fixture.webRTC.connections.count == 2 })

    #expect(fixture.webRTC.liveConnections.count == 1)
    #expect(fixture.webRTC.liveConnections.first === fixture.signaling.peerConnections["bob"])
  }
}
