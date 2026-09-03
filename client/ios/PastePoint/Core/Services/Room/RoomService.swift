//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Combine
import Foundation

@MainActor
final class RoomService: ObservableObject {

  @Published var rooms: [String] = []
  @Published var members: [String] = []
  @Published var currentRoom: String = ""

  private var cancellables = Set<AnyCancellable>()
  private let wsService: WebSocketConnectionService

  private var pendingJoinSpan: TelemetrySpan?
  private var pendingJoinTimeout: Task<Void, Never>?
  private static let joinSpanTimeout: TimeInterval = 10

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
          self?.clearPendingJoinSpan(outcome: .cancelled)
        }
      }
      .store(in: &cancellables)
  }

  func listRooms() async {
    await wsService.send("[UserCommand] /list")
  }

  func joinOrCreateRoom(_ room: String) async {
    guard !room.isEmpty else {
      log.warning("room name is empty — skipped")
      return
    }
    guard room != currentRoom else {
      log.debug("already in room '\(room)' — skipped")
      return
    }
    log.info("Joining room")
    clearPendingJoinSpan(outcome: .superseded)
    if wsService.isConnected {
      startJoinSpan()
    }
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
        log.warning("failed to parse [SystemRooms] message")
        return
      }
      let rest = String(message[range])
      let prefix = "[SystemRooms] "
      let list = rest.hasPrefix(prefix) ? String(rest.dropFirst(prefix.count)) : rest
      rooms = list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
      log.debug("Rooms updated: \(rooms)")
    } else if message.contains("[SystemMembers]") {
      guard let range = message.range(of: "\\[SystemMembers]\\s*(.*)$", options: .regularExpression) else {
        log.warning("failed to parse [SystemMembers] message")
        return
      }
      let rest = String(message[range])
      let prefix = "[SystemMembers] "
      let list = rest.hasPrefix(prefix) ? String(rest.dropFirst(prefix.count)) : rest
      members = list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
      log.debug("Members updated: \(members)")
    } else if message.contains("[SystemJoin]") {
      guard let range = message.range(of: "\\[SystemJoin]\\s*(\\S+)\\s*$", options: .regularExpression) else {
        log.warning("failed to parse [SystemJoin] message")
        return
      }
      let parts = String(message[range]).split(separator: " ")
      guard let last = parts.last else {
        log.warning("[SystemJoin] had no room name")
        return
      }
      currentRoom = String(last)
      log.info("Joined room")
      clearPendingJoinSpan(outcome: .joined)
      Task { await self.listRooms() }
    }
  }

  /// Wire values of the `session.join` span outcome.
  private enum JoinOutcome: String {
    case joined
    case superseded
    case timeout
    case cancelled
  }

  /// Opens the join span with a timeout, since `[SystemJoin]` may never come back.
  private func startJoinSpan() {
    pendingJoinSpan = telemetry.startSpan(op: "session.join", name: "room.join")
    pendingJoinTimeout = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(Self.joinSpanTimeout * 1_000_000_000))
      guard !Task.isCancelled, let self else { return }
      log.warning("join timed out")
      self.clearPendingJoinSpan(outcome: .timeout)
    }
  }

  /// Ends the pending join span (if any) and cancels its timeout.
  private func clearPendingJoinSpan(outcome: JoinOutcome) {
    pendingJoinTimeout?.cancel()
    pendingJoinTimeout = nil
    guard let span = pendingJoinSpan else { return }
    pendingJoinSpan = nil
    telemetry.endSpan(span, ok: outcome == .joined, outcome: outcome.rawValue)
  }
}
