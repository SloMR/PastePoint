//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Combine
import Foundation
import Logging
import SwiftUI

@MainActor
final class WebSocketConnectionService: ObservableObject {
  private let logger = Logger(label: "WebSocket")

  // MARK: - Connection State

  @Published private(set) var isConnected = false
  @Published private(set) var isConnecting = false
  @Published private(set) var isLeavingSession = false

  // MARK: - Message Subjects

  let message = PassthroughSubject<String, Never>()
  let systemMessage = PassthroughSubject<String, Never>()
  let signalMessage = PassthroughSubject<SignalMessage, Never>()
  let didConnect = PassthroughSubject<Void, Never>()
  let didReconnect = PassthroughSubject<Void, Never>()

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
  private let maxReconnectAttempts = 5
  private let baseReconnectDelaySec: Double = 1
  private let maxReconnectDelaySec: Double = 30

  // MARK: - Session Code

  private func clearSessionCode() {
    sessionCode = nil
  }

  func setupPrivateSession(_ code: String) async {
    guard SessionService.isValidSessionCode(code) else {
      logger.warning("Private session code is not valid: \(code)")
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
      logger.debug("Already connecting — ignored")
      isLeavingSession = false
      return
    }

    let effectiveCode = code ?? sessionCode

    if isConnected, sessionCode == effectiveCode {
      logger.debug("Already connected to same session")
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
    if !isReconnectAttempt {
      reconnectAttempts = 0
    }

    let urlString = "wss://\(AppEnvironment.apiUrl)/ws\(effectiveCode.map { "/\($0)" } ?? "")"
    guard let url = URL(string: urlString) else {
      logger.error("Invalid WS URL: \(urlString)")
      isConnecting = false
      return
    }

    logger.info("Connecting to \(urlString)")

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
        self.isConnecting = false
        self.isLeavingSession = false
        if let error {
          self.logger.warning("Connection handshake ping failed: \(error.localizedDescription)")
          self.teardownConnection()
          await self.scheduleReconnect()
        } else {
          self.isConnected = true
          self.didConnect.send()
          if self.hasConnectedOnce {
            self.didReconnect.send()
          }
          self.hasConnectedOnce = true
        }
      }
    }
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
            logger.debug("Binary frame received: \(data.count) bytes (ignored)")
          @unknown default:
            break
          }
        } catch {
          guard !Task.isCancelled else { break }

          if isPermanentError(error) {
            logger.warning("Session code invalid or expired — falling back to public session")
            clearSessionCode()
            teardownConnection()
            await connect(sessionCode: nil, isReconnectAttempt: false)
            break
          }

          logger.error("Receive error: \(error.localizedDescription)")
          await scheduleReconnect()
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
          logger.warning("signal JSON is not a dictionary")
          return
        }
        guard let sig = SignalMessage(from: dict) else {
          logger.warning("malformed SignalMessage — missing required fields in: \(json)")
          return
        }
        signalMessage.send(sig)
      } catch {
        logger.error("JSON parse error: \(error.localizedDescription)")
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
      logger.warning("Send failed — no active socket task")
      return
    }

    do {
      try await task?.send(.string(text))
    } catch {
      logger.error("Send error: \(error.localizedDescription)")
    }
  }

  func sendSignal(_ message: SignalMessage) async {
    do {
      let data = try JSONSerialization.data(withJSONObject: message.toDict())
      guard let json = String(data: data, encoding: .utf8) else {
        logger.error("failed to encode JSON as UTF-8 string")
        return
      }
      await send("[SignalMessage] \(json)")
    } catch {
      logger.error("JSON serialization failed: \(error.localizedDescription)")
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
              logger.warning("Ping failed: \(error.localizedDescription) — triggering reconnect")

              // sendPing callback fires on an arbitrary queue; hop to MainActor.
              Task { @MainActor in
                guard self.isConnected, !self.isConnecting else { return }
                self.teardownConnection()
                await self.scheduleReconnect()
              }
            }
          }
        } catch {
          logger.debug("Ping loop interrupted: \(error.localizedDescription)")
          break
        }
      }
    }
  }

  // MARK: - Teardown

  private func teardownConnection() {
    isConnected = false
    isConnecting = false

    receiveTask?.cancel()
    receiveTask = nil

    pingTask?.cancel()
    pingTask = nil

    task?.cancel(with: .goingAway, reason: nil)
    task = nil
  }

  // MARK: - Reconnect

  private func scheduleReconnect() async {
    isConnected = false
    guard !manualDisconnect, !isConnecting else { return }

    reconnectAttempts += 1
    guard reconnectAttempts <= maxReconnectAttempts else {
      logger.warning("Max reconnect attempts (\(maxReconnectAttempts)) reached — giving up")
      return
    }

    let delay = min(
      baseReconnectDelaySec * pow(2.0, Double(reconnectAttempts - 1)),
      maxReconnectDelaySec,
    )
    logger.info("Reconnecting in \(Int(delay))s (attempt \(reconnectAttempts)/\(maxReconnectAttempts))")

    try? await Task.sleep(for: .seconds(delay))
    guard !manualDisconnect else { return }

    await connect(sessionCode: sessionCode, isReconnectAttempt: true)
  }

  // MARK: - Disconnect

  func disconnect(manual: Bool = true) {
    logger.info("Disconnecting (manual: \(manual))")
    manualDisconnect = manual
    if manual {
      isLeavingSession = true
      clearSessionCode()
    }
    teardownConnection()
  }
}
