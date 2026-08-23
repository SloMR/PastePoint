//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation
import WebRTC

/// Fetches short-lived TURN credentials from `GET /turn-credentials` and caches
/// the resulting ICE server list (STUN + relay) until shortly before the
/// credential expires. Concurrent callers share one in-flight fetch; failures
/// and a 204 (no relay configured) fall back to STUN-only.
@MainActor
final class TurnCredentialsService {
  private struct Response: Decodable {
    let username: String
    let credential: String
    let ttl: Int
    let urls: [String]
  }

  private static let requestTimeout: TimeInterval = 2.0 // Seconds
  private static let retryCooldown: TimeInterval = 30.0 // Seconds

  private var cached: [RTCIceServer]?
  private var expiresAt: Date = .distantPast
  private var nextRetryAt: Date = .distantPast

  /// STUN + a relay when available; cached until just before expiry.
  /// Callers are on the connect path, so a fetch that fails or is slow falls
  /// back to STUN rather than holding up the offer.
  func iceServers() async -> [RTCIceServer] {
    if let cached, Date() < expiresAt { return cached }
    if Date() < nextRetryAt { return WebRTCConfig.stunServers }
    return await load()
  }

  private func load() async -> [RTCIceServer] {
    guard let url = URL(string: AppEnvironment.turnCredentialsUrl) else {
      return WebRTCConfig.stunServers
    }

    do {
      let (data, response) = try await urlSession.data(from: url)
      guard
        let http = response as? HTTPURLResponse,
        (200...299).contains(http.statusCode),
        http.statusCode != 204,
        !data.isEmpty
      else {
        nextRetryAt = Date().addingTimeInterval(Self.retryCooldown)
        log.info("No TURN relay configured on server — STUN-only")
        return WebRTCConfig.stunServers
      }

      let creds = try JSONDecoder().decode(Response.self, from: data)
      guard !creds.urls.isEmpty, !creds.username.isEmpty, !creds.credential.isEmpty else {
        nextRetryAt = Date().addingTimeInterval(Self.retryCooldown)
        log.info("No TURN relay configured on server — STUN-only")
        return WebRTCConfig.stunServers
      }

      let relay = RTCIceServer(
        urlStrings: creds.urls,
        username: creds.username,
        credential: creds.credential,
      )
      let servers = WebRTCConfig.stunServers + [relay]
      cached = servers

      // Refresh a minute before the credential actually expires.
      expiresAt = Date().addingTimeInterval(TimeInterval(max(creds.ttl - 60, 60)))
      log.info("TURN credentials fetched — relay available (ttl \(creds.ttl)s, urls: \(creds.urls.joined(separator: ", ")))")
      return servers
    } catch {
      nextRetryAt = Date().addingTimeInterval(Self.retryCooldown)
      log.debug("TURN fetch failed, STUN-only: \(error.localizedDescription)")
      return WebRTCConfig.stunServers
    }
  }

  private lazy var urlSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = Self.requestTimeout
    config.waitsForConnectivity = false
#if DEBUG
    return URLSession(configuration: config, delegate: InsecureSession(), delegateQueue: nil)
#else
    return URLSession(configuration: config)
#endif
  }()
}
