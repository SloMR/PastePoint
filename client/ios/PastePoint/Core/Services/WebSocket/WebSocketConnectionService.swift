//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Combine
import Foundation
import SwiftUI

struct ReconnectState: Equatable {
  let attempt: Int
  let nextAttemptDate: Date
}

@MainActor
final class WebSocketConnectionService: ObservableObject {

  // MARK: - Connection State

  @Published private(set) var isConnected = false
  @Published private(set) var isConnecting = false
  @Published private(set) var isLeavingSession = false
  @Published private(set) var reconnectState: ReconnectState?

  // MARK: - Message Subjects

  let message = PassthroughSubject<String, Never>()
  let systemMessage = PassthroughSubject<String, Never>()
  let signalMessage = PassthroughSubject<SignalMessage, Never>()
  let didConnect = PassthroughSubject<Void, Never>()
  let didReconnect = PassthroughSubject<Void, Never>()
  let sessionRejected = PassthroughSubject<Void, Never>()

  // MARK: - Properties

  private var task: URLSessionWebSocketTask?
  private var receiveTask: Task<Void, Never>?

  private var pingTask: Task<Void, Never>?
  private let pingInterval: Duration = .seconds(30)

  @Published private(set) var sessionCode: String?
  var currentSessionCode: String? { sessionCode }

  private var manualDisconnect = false
  private var hasConnectedOnce = false
  private var reconnectAttempts = 0
  private var reconnectTask: Task<Void, Never>?
  private let maxReconnectAttempts = 5
  private let baseReconnectDelaySec: Double = 1
  private let maxReconnectDelaySec: Double = 30
  private var connectSpan: TelemetrySpan?

  // MARK: - Session Code

  private func clearSessionCode() {
    sessionCode = nil
  }

  func setupPrivateSession(_ code: String) async {
    guard SessionService.isValidSessionCode(code) else {
      log.warning("Private session code is not valid")
      return
    }
    disconnect(manual: true)
    sessionCode = SessionService.sanitizeSessionCode(code)
  }

  // MARK: - Connect

  func connect(sessionCode code: String? = nil, isReconnectAttempt: Bool = false) async {
#if DEBUG
    guard !AppBuildInfo.isXcodePreview else { return }
#endif

    guard !isConnecting else {
      log.debug("Already connecting — ignored")
      isLeavingSession = false
      return
    }

    let effectiveCode = code ?? sessionCode

    if isConnected, sessionCode == effectiveCode {
      log.debug("Already connected to same session")
      isLeavingSession = false
      return
    }

    // Tear down any existing task before opening a new one.
    if task != nil {
      teardownConnection()
    }

    isConnecting = true
    manualDisconnect = false
    sessionCode = effectiveCode

    // Reset the retry counter on every intentional (non-reconnect) connect so
    // that NWPathMonitor / foreground transitions always get a fresh 5-attempt window.
    let priorAttempts = reconnectAttempts
    if !isReconnectAttempt {
      reconnectAttempts = 0
    }

    let urlString = AppEnvironment.webSocketUrl(sessionCode: effectiveCode)
    guard let url = URL(string: urlString) else {
      log.error("Invalid WS URL")
      isConnecting = false
      return
    }

    log.info("Connecting (private: \(effectiveCode != nil))")

    connectSpan = telemetry.startSpan(op: "ws.connect", attributes: [
      "ws.has_session_code": effectiveCode != nil,
      "attempt": priorAttempts,
    ])

#if DEBUG
    let session = URLSession(
      configuration: .default,
      delegate: InsecureSession(),
      delegateQueue: nil,
    )
#else
    let session = URLSession(configuration: .default)
#endif

    task = session.webSocketTask(with: url)
    task?.resume()

    startReceiveLoop()
    startPingLoop()

    // Keep isConnecting = true until the handshake ping returns so that
    // concurrent handleForeground() calls stay blocked during this window.
    let capturedTask = task
    capturedTask?.sendPing { [weak self] error in
      Task { @MainActor [weak self] in
        guard let self, self.task === capturedTask else { return }
        await self.handleHandshake(error: error, priorAttempts: priorAttempts)
      }
    }
  }

  /// Settles a connect attempt once the handshake ping returns.
  private func handleHandshake(error: (any Error)?, priorAttempts: Int) async {
    isConnecting = false
    isLeavingSession = false

    guard let error else {
      endConnectSpan(.opened)
      isConnected = true
      reconnectState = nil
      didConnect.send()
      if priorAttempts > 0 {
        telemetry.event("ws.reconnected", attributes: ["attempts": priorAttempts])
      }
      if hasConnectedOnce {
        didReconnect.send()
      }
      hasConnectedOnce = true
      return
    }

    log.warning("Connection handshake ping failed: \(error.localizedDescription)")
    let rejected = isPermanentError(error)
    endConnectSpan(rejected ? .sessionRejected : .handshakeFailed)
    teardownConnection()
    if rejected {
      log.warning("Session code invalid or expired — falling back to public session")
      telemetry.warnEvent("session.fallback_public", attributes: ["attempts": reconnectAttempts])
      sessionRejected.send()
      clearSessionCode()
      await connect(sessionCode: nil, isReconnectAttempt: false)
      return
    }
    scheduleReconnect()
  }

  // MARK: - Receive Loop

  private func startReceiveLoop() {
    receiveTask?.cancel()
    receiveTask = Task {
      while !Task.isCancelled {
        do {
          guard let msg = try await task?.receive() else { break }

          // Any successful receive confirms the connection is alive —
          // reset the retry counter so future drops get a fresh window.
          reconnectAttempts = 0

          switch msg {
          case .string(let text):
            handleIncoming(text)
          case .data(let data):
            log.debug("Binary frame received: \(data.count) bytes (ignored)")
          @unknown default:
            break
          }
        } catch {
          guard !Task.isCancelled else { break }

          if isPermanentError(error) {
            log.warning("Session code invalid or expired — falling back to public session")
            endConnectSpan(.sessionRejected)
            telemetry.warnEvent("session.fallback_public", attributes: ["attempts": reconnectAttempts])
            sessionRejected.send()
            clearSessionCode()
            teardownConnection()
            await connect(sessionCode: nil, isReconnectAttempt: false)
            break
          }

          log.error("Receive error: \(error.localizedDescription)")
          scheduleReconnect()
          break
        }
      }
    }
  }

  private func isPermanentError(_ error: Error) -> Bool {
    (error as? URLError)?.code == .badServerResponse
  }

  // MARK: - Message Routing

  private func handleIncoming(_ text: String) {
    let msg = text.trimmingCharacters(in: .whitespacesAndNewlines)

    if msg.hasPrefix("[SignalMessage]") {
      let json = msg
        .replacingOccurrences(of: "[SignalMessage]", with: "")
        .trimmingCharacters(in: .whitespaces)
      do {
        let obj = try JSONSerialization.jsonObject(with: Data(json.utf8))
        guard let dict = obj as? [String: Any] else {
          log.warning("signal JSON is not a dictionary")
          return
        }
        guard let sig = SignalMessage(from: dict) else {
          log.warning("malformed SignalMessage — missing required fields")
          return
        }
        signalMessage.send(sig)
      } catch {
        log.error("JSON parse error: \(error.localizedDescription)")
      }
    } else if isSystemMessage(msg) {
      systemMessage.send(msg)
    } else {
      message.send(msg)
    }
  }

  private func isSystemMessage(_ msg: String) -> Bool {
    msg.contains("[SystemMessage]") ||
      msg.contains("[SystemJoin]") ||
      msg.contains("[SystemRooms]") ||
      msg.contains("[SystemMembers]") ||
      msg.contains("[SystemName]")
  }

  // MARK: - Send

  func send(_ text: String) async {
#if DEBUG
    guard !AppBuildInfo.isXcodePreview else { return }
#endif

    guard task != nil else {
      log.warning("Send failed — no active socket task")
      return
    }

    do {
      try await task?.send(.string(text))
    } catch {
      log.error("Send error: \(error.localizedDescription)")
    }
  }

  func sendSignal(_ message: SignalMessage) async {
    do {
      let data = try JSONSerialization.data(withJSONObject: message.toDict())
      guard let json = String(data: data, encoding: .utf8) else {
        log.error("failed to encode JSON as UTF-8 string")
        return
      }
      await send("[SignalMessage] \(json)")
    } catch {
      log.error("JSON serialization failed: \(error.localizedDescription)")
    }
  }

  // MARK: - Ping / Heartbeat

  private func startPingLoop() {
    pingTask?.cancel()

    pingTask = Task {
      while !Task.isCancelled {
        do {
          try await Task.sleep(for: pingInterval)
          guard !Task.isCancelled, isConnected else { break }

          task?.sendPing { [weak self] error in
            guard let self else { return }
            if let error {
              log.warning("Ping failed: \(error.localizedDescription) — triggering reconnect")

              // sendPing callback fires on an arbitrary queue; hop to MainActor.
              Task { @MainActor in
                guard self.isConnected, !self.isConnecting else { return }
                self.teardownConnection()
                self.scheduleReconnect()
              }
            }
          }
        } catch {
          log.debug("Ping loop interrupted: \(error.localizedDescription)")
          break
        }
      }
    }
  }

  // MARK: - Teardown

  private func teardownConnection() {
    isConnected = false
    isConnecting = false

    // A span still open here is an attempt that never settled (disconnect / superseding connect).
    endConnectSpan(.cancelled)

    reconnectTask?.cancel()
    reconnectTask = nil

    receiveTask?.cancel()
    receiveTask = nil

    pingTask?.cancel()
    pingTask = nil

    task?.cancel(with: .goingAway, reason: nil)
    task = nil
  }

  /// How a `ws.connect` attempt settled.
  private enum ConnectSpanEnd {
    case opened
    case sessionRejected
    case handshakeFailed
    case cancelled
  }

  /// Ends the open connect span (if any); later calls for the same attempt are no-ops.
  private func endConnectSpan(_ end: ConnectSpanEnd) {
    switch end {
    case .opened: telemetry.endSpan(connectSpan, ok: true)
    case .sessionRejected: telemetry.endSpan(connectSpan, ok: false, message: "session_rejected")
    case .handshakeFailed: telemetry.endSpan(connectSpan, ok: false, message: "handshake_failed")
    case .cancelled: telemetry.endSpan(connectSpan, ok: false, outcome: "cancelled")
    }
    connectSpan = nil
  }

  // MARK: - Reconnect

  private func scheduleReconnect() {
    isConnected = false
    guard !manualDisconnect, !isConnecting else { return }

    reconnectAttempts += 1
    let delay = reconnectAttempts <= maxReconnectAttempts
      ? min(baseReconnectDelaySec * pow(2.0, Double(reconnectAttempts - 1)), maxReconnectDelaySec)
      : maxReconnectDelaySec
    log.info("Reconnecting in \(Int(delay))s (attempt \(reconnectAttempts))")
    reconnectState = ReconnectState(attempt: reconnectAttempts, nextAttemptDate: Date().addingTimeInterval(delay))

    reconnectTask?.cancel()
    reconnectTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(delay))
      guard !Task.isCancelled, let self, !self.manualDisconnect else { return }
      await self.connect(sessionCode: self.sessionCode, isReconnectAttempt: true)
    }
  }

  // MARK: - Disconnect

  func disconnect(manual: Bool = true) {
    log.info("Disconnecting (manual: \(manual))")
    manualDisconnect = manual
    reconnectState = nil
    reconnectAttempts = 0
    if manual {
      isLeavingSession = true
      clearSessionCode()
    }
    teardownConnection()
  }
}
