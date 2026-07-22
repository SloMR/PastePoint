//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation

enum AppEnvironment {

  // MARK: - Base Hosts

#if DEBUG
  private static let host = "127.0.0.1"
  private static let wsPort: Int? = 9000
#else
  private static let host = "pastepoint.com"
  private static let wsPort: Int? = nil
#endif

  private static var webUrl: String { host }
  private static let privateSessionPath = "private"
  private static var apiUrl: String {
    if let port = wsPort { return "\(host):\(port)" }
    return host
  }

  // MARK: - API Endpoints

  /// Used for requesting a new private session code.
  static var createSessionUrl: String { "https://\(apiUrl)/create-session" }

  /// Used for the launch-time client version/update-policy check.
  static var versionUrl: String { "https://\(apiUrl)/version" }

  /// Used for fetching short-lived TURN relay credentials.
  static var turnCredentialsUrl: String { "https://\(apiUrl)/turn-credentials" }

  /// Used for connecting to the signaling WebSocket.
  static func webSocketUrl(sessionCode: String?) -> String {
    "wss://\(apiUrl)/ws\(sessionCode.map { "/\($0)" } ?? "")"
  }

  // MARK: - Local Network

  /// Used for local network permission probing.
  static var localNetworkProbeHost: String { host }

  /// Used for local network permission probing.
  static var localNetworkProbePort: Int { wsPort ?? 443 }

  // MARK: - Web URLs

  /// Used for legal pages, matching the active web host in debug and release.
  static var legalUrl: String { "https://\(webUrl)/privacy?app=1" }

  /// Used for QR codes that invite another device into a private session.
  static func privateSessionUrl(sessionCode: String) -> String {
    "https://\(webUrl)/\(privateSessionPath)/\(sessionCode)"
  }

  // MARK: - Support

  /// Destination for user-submitted reports of objectionable content.
  static let supportEmail = "support@pastepoint.com"

  // MARK: - URL Parsing

  /// Extracts the session code candidate from a PastePoint private-session URL.
  static func privateSessionCode(from payload: String) -> String? {
    let trimmedPayload = payload.trimmingCharacters(in: .whitespacesAndNewlines)

    guard
      let url = URL(string: trimmedPayload),
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      components.scheme == "https",
      components.host == webUrl
    else { return nil }

    let pathComponents = components.path
      .split(separator: "/")
      .map(String.init)

    guard pathComponents.count == 2, pathComponents[0] == privateSessionPath else {
      return nil
    }

    return pathComponents[1]
  }
}
