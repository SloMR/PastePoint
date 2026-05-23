//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Combine
import Foundation
import Logging

@MainActor
final class UserService: ObservableObject {
  private let logger = Logger(label: "User")

  @Published var user: String = ""

  private let wsService: WebSocketConnectionService
  private var cancellables = Set<AnyCancellable>()
  private static let nameRegex = try? NSRegularExpression(pattern: "\\[SystemName]\\s*(.*?)$")

  init(wsService: WebSocketConnectionService) {
    self.wsService = wsService

    wsService.systemMessage
      .receive(on: DispatchQueue.main)
      .sink { [weak self] message in
        self?.handleSystemMessage(message)
      }
      .store(in: &cancellables)

    wsService.didConnect
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        Task { await self?.getUsername() }
      }
      .store(in: &cancellables)
  }

  func getUsername() async {
    await wsService.send("[UserCommand] /name")
  }

  /// Suspends until `user` is non-empty. Returns immediately if already set.
  /// Used by services that need the username before sending peer messages —
  /// covers the race where the server's `[SystemName]` arrives after a peer event.
  func waitForUsername() async {
    if !user.isEmpty { return }
    for await name in $user.values where !name.isEmpty {
      return
    }
  }

  private func handleSystemMessage(_ message: String) {
    guard message.contains("[SystemName]") else { return }
    guard let regex = Self.nameRegex else {
      logger.error("nameRegex failed to initialize")
      return
    }
    guard let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)) else {
      logger.warning("no [SystemName] match in: \(message)")
      return
    }
    guard let range = Range(match.range(at: 1), in: message) else {
      logger.warning("capture group out of range in: \(message)")
      return
    }
    user = String(message[range]).trimmingCharacters(in: .whitespaces)
    logger.debug("Username updated: \(user)")
  }
}
