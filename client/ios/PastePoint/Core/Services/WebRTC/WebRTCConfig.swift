//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation
import WebRTC

enum WebRTCConfig {
  static let maxBufferedAmount: UInt64 = 2 * 1024 * 1024 // 2MB
  static let bufferedAmountLowThreshold: UInt64 = 1 * 1024 * 1024 // 1MB

  static let iceServers: [RTCIceServer] = [
    RTCIceServer(urlStrings: [
      // Google STUN servers
      "stun:stun.l.google.com:19302",
      "stun:stun1.l.google.com:19302",
      "stun:stun2.l.google.com:19302",
      "stun:stun3.l.google.com:19302",
      "stun:stun4.l.google.com:19302",
      // Third-party/public STUN servers
      "stun:stun.voipbuster.com",
      "stun:stun.services.mozilla.com",
      "stun:stun.stunprotocol.org:3478",
      "stun:stun.iptel.org",
    ]),

    // Open Relay Project TURN servers
    RTCIceServer(
      urlStrings: [
        "turn:openrelay.metered.ca:80",
        "turn:openrelay.metered.ca:443",
        "turns:openrelay.metered.ca:443",
      ],
      username: "openrelayproject",
      credential: "openrelayproject",
    ),

  ]

  static let peerConnectionConfig: RTCConfiguration = {
    let config = RTCConfiguration()
    config.iceServers = iceServers
    config.sdpSemantics = .unifiedPlan
    config.bundlePolicy = .maxBundle
    config.rtcpMuxPolicy = .require
    return config
  }()

  static let dataChannelConfig: RTCDataChannelConfiguration = {
    let config = RTCDataChannelConfiguration()
    config.isOrdered = true
    config.maxPacketLifeTime = 30_000
    return config
  }()
}
