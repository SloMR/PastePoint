//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Combine
import Network
import SwiftUI
import UIKit
import WebRTC

@MainActor
final class AppServices: ObservableObject {

  @Published private(set) var localNetworkDenied = false

  static let shared = AppServices()

  let wsService: WebSocketConnectionService
  let sessionService: SessionService

  let userService: UserService
  let signalingService: SignalingService

  let roomService: RoomService
  let blockService: BlockService

  let peerDirectory: PeerDirectory
  let fileTransferService: FileTransferService

  let connectionWarningMonitor: ConnectionWarningMonitor
  let updateService: AppUpdateService

  private var isInBackground = false
  private var isForegroundHandling = false
  private var isDisconnectedForUpdate = false
  private var didReportUpdateGate = false

  private let networkMonitor = NWPathMonitor()
  private var lastPathStatus: NWPath.Status = .satisfied
  private var cancellables = Set<AnyCancellable>()

  private static let backgroundGraceInterval: Duration = .seconds(10)
  private var backgroundGraceTask: Task<Void, Never>?
  private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

  private init() {
    wsService = WebSocketConnectionService()
    sessionService = SessionService(wsService: wsService)

    userService = UserService(wsService: wsService)
    roomService = RoomService(wsService: wsService)

    blockService = BlockService(wsService: wsService)

    peerDirectory = PeerDirectory(roomService: roomService, userService: userService, blockService: blockService)
    signalingService = SignalingService(
      wsService: wsService,
      userService: userService,
      peerDirectory: peerDirectory,
      blockService: blockService,
    )

    fileTransferService = FileTransferService(
      signalingService: signalingService,
      userService: userService,
      peerDirectory: peerDirectory,
    )

    connectionWarningMonitor = ConnectionWarningMonitor(
      peerDirectory: peerDirectory,
      signalingService: signalingService,
    )

    updateService = AppUpdateService()

#if DEBUG
    guard !AppBuildInfo.isXcodePreview else {
      forwardServiceChanges()
      return
    }
#endif

    startNetworkMonitoring()
    startTerminationObserver()
    startUpdateGateObserver()
    forwardServiceChanges()
  }

#if DEBUG
  /// Preview-only: no WebSocket connection, no network monitoring, no lifecycle observers.
  private init(preview _: Bool) {
    wsService = WebSocketConnectionService()
    sessionService = SessionService(wsService: wsService)

    userService = UserService(wsService: wsService)
    roomService = RoomService(wsService: wsService)

    blockService = BlockService(wsService: wsService)
    peerDirectory = PeerDirectory(roomService: roomService, userService: userService, blockService: blockService)

    signalingService = SignalingService(
      wsService: wsService,
      userService: userService,
      peerDirectory: peerDirectory,
      blockService: blockService,
    )

    fileTransferService = FileTransferService(
      signalingService: signalingService,
      userService: userService,
      peerDirectory: peerDirectory,
    )

    connectionWarningMonitor = ConnectionWarningMonitor(
      peerDirectory: peerDirectory,
      signalingService: signalingService,
    )

    updateService = AppUpdateService()

    forwardServiceChanges()
  }

  static var preview: AppServices {
    AppLogging.bootstrap()
    let services = AppServices(preview: true)
    services.userService.user = "Alice"
    services.roomService.rooms = ["General", "Random", "Dev"]
    services.roomService.currentRoom = "General"
    services.roomService.members = ["Alice", "Bob", "Charlie"]
    return services
  }
#endif

  // MARK: - App Lifecycle

  func handleForeground() async {
#if DEBUG
    guard !AppBuildInfo.isXcodePreview else { return }
#endif

    isInBackground = false
    endBackgroundGrace()

    guard LegalConsent.isAccepted else {
      log.debug("handleForeground — terms not accepted, staying offline")
      return
    }

    guard !wsService.isConnected, !wsService.isConnecting, !isForegroundHandling else {
      log.debug("handleForeground — already connected or connecting, skipping")
      return
    }
    isForegroundHandling = true
    defer { isForegroundHandling = false }
    await connectIfPermitted(sessionCode: wsService.currentSessionCode)
  }

  func clearLocalNetworkDenied() {
    localNetworkDenied = false
  }

  @discardableResult
  func connectIfPermitted(sessionCode: String? = nil) async -> Bool {
#if DEBUG
    guard !AppBuildInfo.isXcodePreview else {
      await wsService.connect(sessionCode: sessionCode)
      return true
    }
#endif

    if case .required = updateService.recommendation {
      log.warning("connectIfPermitted — update required, skipping connect")
      reportUpdateGate()
      return false
    }

    let denied = await LocalNetworkPermission.isDenied()
    localNetworkDenied = denied
    guard !denied else {
      log.warning("connectIfPermitted — local network denied, skipping connect")
      wsService.disconnect(manual: false)
      return false
    }

    await wsService.connect(sessionCode: sessionCode)
    return true
  }

  func handleBackground() {
    log.info("handleBackground — starting disconnect grace window")
    isInBackground = true

    backgroundGraceTask?.cancel()
    backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "pastepoint.disconnectgrace") { [weak self] in
      self?.backgroundGraceTask?.cancel()
      self?.performBackgroundDisconnect()
    }

    backgroundGraceTask = Task { [weak self] in
      try? await Task.sleep(for: Self.backgroundGraceInterval)
      guard !Task.isCancelled else { return }
      self?.performBackgroundDisconnect()
    }
  }

  /// Teardown, run once the grace window elapses
  private func performBackgroundDisconnect() {
    guard backgroundTaskID != .invalid else { return }
    log.info("handleBackground — grace elapsed, disconnecting")
    fileTransferService.cancelAllTransfers()
    wsService.disconnect(manual: false)
    endBackgroundGrace()
  }

  /// Cancels a pending grace timer and releases the background-task assertion.
  private func endBackgroundGrace() {
    backgroundGraceTask?.cancel()
    backgroundGraceTask = nil
    if backgroundTaskID != .invalid {
      UIApplication.shared.endBackgroundTask(backgroundTaskID)
      backgroundTaskID = .invalid
    }
  }

  // MARK: - Network Monitoring

  /// Watches for network restoration and reconnects automatically —
  /// covers the case where the reconnect loop exhausted its attempts
  /// while the network was down, then the network came back.
  private func startNetworkMonitoring() {
    networkMonitor.pathUpdateHandler = { [weak self] path in
      Task { @MainActor [weak self] in
        guard let self else { return }

        let previous = self.lastPathStatus
        self.lastPathStatus = path.status

        if previous != path.status {
          log.debug("Network path changed: \(previous) → \(path.status)")
        }

        guard path.status == .satisfied, previous != .satisfied else { return }
        guard !self.isInBackground else { return }

        log.info("Network restored — triggering reconnect")
        await self.handleForeground()
      }
    }
    networkMonitor.start(queue: DispatchQueue(label: "com.pastepoint.NetworkMonitor"))
  }

  // MARK: - Update Gate

  /// Tears down the connection while a required update is pending; resumes when it clears.
  private func startUpdateGateObserver() {
    updateService.$recommendation
      .sink { [weak self] recommendation in
        guard let self else { return }
        if case .required = recommendation {
          guard self.wsService.isConnected || self.wsService.isConnecting else { return }
          log.warning("Update required — disconnecting until the app is updated")
          self.reportUpdateGate()
          self.isDisconnectedForUpdate = true
          self.wsService.disconnect(manual: false)
        } else {
          self.didReportUpdateGate = false
          if self.isDisconnectedForUpdate {
            self.isDisconnectedForUpdate = false
            Task { await self.handleForeground() }
          }
        }
      }
      .store(in: &cancellables)
  }

  /// Counts a required-update gate once per episode; foreground retries while gated must not re-count it.
  private func reportUpdateGate() {
    guard !didReportUpdateGate else { return }
    didReportUpdateGate = true
    telemetry.warnEvent("update.gate_blocked")
  }

  // MARK: - Termination

  private func startTerminationObserver() {
    NotificationCenter.default
      .publisher(for: UIApplication.willTerminateNotification)
      .sink { [weak self] _ in
        self?.wsService.disconnect(manual: true)
        RTCCleanupSSL()
      }
      .store(in: &cancellables)
  }

  // MARK: - Change Forwarding

  private func forwardServiceChanges() {
    wsService.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &cancellables)

    userService.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &cancellables)

    roomService.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &cancellables)

    blockService.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &cancellables)

    signalingService.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &cancellables)

    fileTransferService.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &cancellables)

    connectionWarningMonitor.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &cancellables)

    updateService.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &cancellables)
  }
}
