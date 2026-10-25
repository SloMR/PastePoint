//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Clocks
import Foundation
import Testing
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
}
