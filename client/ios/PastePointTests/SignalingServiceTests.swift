//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Clocks
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
}
