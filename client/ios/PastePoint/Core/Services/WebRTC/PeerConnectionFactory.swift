//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation
import WebRTC

// `@unchecked Sendable`: the wrapped `RTCPeerConnectionFactory` is internally
// thread-safe (libwebrtc handles its own locking), and our only stored property
// is `let factory`. Safe to share across actors.
final class PeerConnectionFactory: @unchecked Sendable {
  static let shared = PeerConnectionFactory()

  private let factory: RTCPeerConnectionFactory

  private init() {
    RTCInitializeSSL() // TODO: Don't forget to clean it even the OS will do it for you
    factory = RTCPeerConnectionFactory(encoderFactory: nil, decoderFactory: nil)
  }

  func makePeerConnection(delegate: RTCPeerConnectionDelegate) -> RTCPeerConnection? {
    let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
    return factory.peerConnection(
      with: WebRTCConfig.peerConnectionConfig,
      constraints: constraints,
      delegate: delegate,
    )
  }
}
