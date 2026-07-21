//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation
import WebRTC

enum WebRTCConfig {
  static let maxBufferedAmount: UInt64 = 16 * 1024 * 1024 // 16MB
  static let bufferedAmountLowThreshold: UInt64 = 8 * 1024 * 1024 // 8MB

  static let iceServers: [RTCIceServer] = [
    // Public STUN servers
    RTCIceServer(urlStrings: [
      "stun:stun.l.google.com:19302",
      "stun:stun.cloudflare.com:3478",
      "stun:global.stun.twilio.com:3478",
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
    return config
  }()
}
