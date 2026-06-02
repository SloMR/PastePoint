//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Combine
import Logging
import Network
import SwiftUI
import UIKit
import WebRTC

@MainActor
final class AppServices: ObservableObject {
  private let logger = Logger(label: "App")

  let wsService: WebSocketConnectionService
  let sessionService: SessionService
  let userService: UserService
  let signalingService: SignalingService
  let roomService: RoomService
  let peerDirectory: PeerDirectory
  let fileTransferService: FileTransferService

  static let shared = AppServices()

  @Published private(set) var localNetworkDenied = false

  private var isInBackground = false
  private var isForegroundHandling = false
  private let networkMonitor = NWPathMonitor()
  private var cancellables = Set<AnyCancellable>()

  private init() {
    wsService = WebSocketConnectionService()
    sessionService = SessionService()
    userService = UserService(wsService: wsService)
    roomService = RoomService(wsService: wsService)
    peerDirectory = PeerDirectory(roomService: roomService, userService: userService)
    signalingService = SignalingService(wsService: wsService, userService: userService, peerDirectory: peerDirectory)
    fileTransferService = FileTransferService(
      signalingService: signalingService,
      userService: userService,
      peerDirectory: peerDirectory,
    )

#if DEBUG
    guard !AppBuildInfo.isXcodePreview else {
      forwardServiceChanges()
      return
    }
#endif

    startNetworkMonitoring()
    startTerminationObserver()
    forwardServiceChanges()
  }

#if DEBUG
  /// Preview-only: no WebSocket connection, no network monitoring, no lifecycle observers.
  private init(preview _: Bool) {
    wsService = WebSocketConnectionService()
    sessionService = SessionService()
    userService = UserService(wsService: wsService)
    roomService = RoomService(wsService: wsService)
    peerDirectory = PeerDirectory(roomService: roomService, userService: userService)
    signalingService = SignalingService(wsService: wsService, userService: userService, peerDirectory: peerDirectory)
    fileTransferService = FileTransferService(
      signalingService: signalingService,
      userService: userService,
      peerDirectory: peerDirectory,
    )

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
    guard !wsService.isConnected, !wsService.isConnecting, !isForegroundHandling else {
      logger.debug("handleForeground — already connected or connecting, skipping")
      return
    }
    isForegroundHandling = true
    defer { isForegroundHandling = false }
    let denied = await LocalNetworkPermission.isDenied()
    localNetworkDenied = denied
    guard !denied else {
      logger.warning("handleForeground — local network permission denied, skipping connect")
      wsService.disconnect(manual: false)
      return
    }
    logger.info("handleForeground — connecting")
    await wsService.connect(sessionCode: wsService.currentSessionCode)
  }

  func clearLocalNetworkDenied() {
    localNetworkDenied = false
  }

  func handleBackground() {
    logger.info("handleBackground — disconnecting")
    isInBackground = true
    wsService.disconnect(manual: false)
  }

  // MARK: - Network Monitoring

  /// Watches for network restoration and reconnects automatically —
  /// covers the case where the reconnect loop exhausted its attempts
  /// while the network was down, then the network came back.
  private func startNetworkMonitoring() {
    networkMonitor.pathUpdateHandler = { [weak self] path in
      self?.logger.debug("Network path updated: \(path.status)")
      guard path.status == .satisfied else { return }
      Task { @MainActor [weak self] in
        guard let self, !self.isInBackground else { return }
        self.logger.info("Network restored — triggering reconnect")
        await self.handleForeground()
      }
    }
    networkMonitor.start(queue: DispatchQueue(label: "com.pastepoint.NetworkMonitor"))
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
    signalingService.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &cancellables)
    fileTransferService.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &cancellables)
  }
}
