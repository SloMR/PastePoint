//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation
import WebRTC

enum WebRTCConfig {
  static let iceServers: [RTCIceServer] = [
    RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"]) // TODO: Add more RTC Servers.
    
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
