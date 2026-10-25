//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Combine
@testable import PastePoint

@MainActor
final class MockSignalTransport: SignalTransport {
  let signalMessage = PassthroughSubject<SignalMessage, Never>()
  let didConnect = PassthroughSubject<Void, Never>()
  let currentSessionCode: String? = nil
  private(set) var sent: [SignalMessage] = []

  func sendSignal(_ message: SignalMessage) async {
    sent.append(message)
  }
}
