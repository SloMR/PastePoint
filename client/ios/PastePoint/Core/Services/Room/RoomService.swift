//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Combine
import Foundation
import Logging

@MainActor
final class RoomService: ObservableObject {
  private let logger = Logger(label: "Room")

  @Published var rooms: [String] = []
  @Published var members: [String] = []
  @Published var currentRoom: String = ""

  private var cancellables = Set<AnyCancellable>()
  private let wsService: WebSocketConnectionService

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
        Task { await self?.listRooms() }
      }
      .store(in: &cancellables)

    wsService.$isConnected
      .receive(on: DispatchQueue.main)
      .sink { [weak self] connected in
        if !connected {
          self?.members = []
        }
      }
      .store(in: &cancellables)
  }

  func listRooms() async {
    await wsService.send("[UserCommand] /list")
  }

  func joinOrCreateRoom(_ room: String) async {
    guard !room.isEmpty else {
      logger.warning("room name is empty — skipped")
      return
    }
    guard room != currentRoom else {
      logger.debug("already in room '\(room)' — skipped")
      return
    }
    logger.info("Joining room: \(room)")
    await wsService.send("[UserCommand] /join \(room)")
    currentRoom = room

#if DEBUG
    if AppBuildInfo.isXcodePreview {
      if !rooms.contains(room) { rooms.append(room) }
      return
    }
#endif

    await listRooms()
  }

  private func handleSystemMessage(_ message: String) {
    if message.contains("[SystemRooms]") {
      guard let range = message.range(of: "\\[SystemRooms]\\s*(.*)$", options: .regularExpression) else {
        logger.warning("failed to parse [SystemRooms] message: \(message)")
        return
      }
      let rest = String(message[range])
      let prefix = "[SystemRooms] "
      let list = rest.hasPrefix(prefix) ? String(rest.dropFirst(prefix.count)) : rest
      rooms = list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
      logger.debug("Rooms updated: \(rooms)")
    } else if message.contains("[SystemMembers]") {
      guard let range = message.range(of: "\\[SystemMembers]\\s*(.*)$", options: .regularExpression) else {
        logger.warning("failed to parse [SystemMembers] message: \(message)")
        return
      }
      let rest = String(message[range])
      let prefix = "[SystemMembers] "
      let list = rest.hasPrefix(prefix) ? String(rest.dropFirst(prefix.count)) : rest
      members = list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
      logger.debug("Members updated: \(members)")
    } else if message.contains("[SystemJoin]") {
      guard let range = message.range(of: "\\[SystemJoin]\\s*(\\S+)\\s*$", options: .regularExpression) else {
        logger.warning("failed to parse [SystemJoin] message: \(message)")
        return
      }
      let parts = String(message[range]).split(separator: " ")
      guard let last = parts.last else {
        logger.warning("[SystemJoin] had no room name in: \(message)")
        return
      }
      currentRoom = String(last)
      logger.info("Joined room: \(currentRoom)")
      Task { await self.listRooms() }
    }
  }
}
