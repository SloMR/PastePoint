//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation
import WebRTC

enum WebRTCConfig {
  static let maxBufferedAmount: UInt64 = 16 * 1024 * 1024 // 16MB
  static let bufferedAmountLowThreshold: UInt64 = 8 * 1024 * 1024 // 8MB

  /// Public STUN servers only.
  static let stunServers: [RTCIceServer] = [
    RTCIceServer(urlStrings: [
      "stun:stun.l.google.com:19302",
      "stun:stun.cloudflare.com:3478",
      "stun:global.stun.twilio.com:3478",
    ]),
  ]

  /// Builds a peer-connection config with the given ICE servers (STUN, plus a
  /// relay when credentials are available).
  static func makeConfiguration(iceServers: [RTCIceServer]) -> RTCConfiguration {
    let config = RTCConfiguration()
    config.iceServers = iceServers
    config.sdpSemantics = .unifiedPlan
    config.bundlePolicy = .maxBundle
    config.rtcpMuxPolicy = .require
    config.iceCandidatePoolSize = 10
    return config
  }

  static let dataChannelConfig: RTCDataChannelConfiguration = {
    let config = RTCDataChannelConfiguration()
    config.isOrdered = true
    return config
  }()
}
