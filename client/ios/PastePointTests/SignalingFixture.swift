//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Clocks
import Combine
@testable import PastePoint

@MainActor
struct SignalingFixture {
  let me = "alice"
  let transport = MockSignalTransport()
  let webRTC = MockWebRTCEngine()
  let clock = TestClock()
  let signaling: SignalingService
  private let roomService: RoomService

  init() async {
    let ws = WebSocketConnectionService()
    let userService = UserService(wsService: ws)
    let blockService = BlockService(wsService: ws)
    roomService = RoomService(wsService: ws)
    signaling = SignalingService(
      wsService: transport,
      userService: userService,
      peerDirectory: PeerDirectory(
        roomService: roomService,
        userService: userService,
        blockService: blockService,
      ),
      blockService: blockService,
      turnCredentials: MockIceServerSource(),
      webRTC: webRTC,
      clock: clock,
    )

    ws.systemMessage.send("\(WebSocketPrefix.systemName.rawValue) \(me)")
    _ = await waitUntil { userService.user == me }
  }

  func setPeers(_ peers: [String]) {
    roomService.members = [me] + peers
  }

  /// Lets the app's queued work run, checking `condition` after each turn (at most 1,000 turns).
  func waitUntil(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<1_000 {
      if condition() { return true }
      await Task.yield()
    }
    return false
  }
}
