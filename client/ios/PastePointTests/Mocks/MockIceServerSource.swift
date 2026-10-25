//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

@preconcurrency import WebRTC
@testable import PastePoint

struct MockIceServerSource: IceServerSource {
  func iceServers() async -> [RTCIceServer] {
    []
  }
}
