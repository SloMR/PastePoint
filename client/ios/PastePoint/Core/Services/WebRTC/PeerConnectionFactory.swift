//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation
import WebRTC

final class PeerConnectionFactory {
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
      delegate: delegate
    )
  }
}
