//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Combine
import Foundation

/// Server response; do not rename fields.
struct CreateSessionResponse: Decodable {
  let code: String
}

@MainActor
final class SessionService: ObservableObject {
  private let wsService: WebSocketConnectionService

  init(wsService: WebSocketConnectionService) {
    self.wsService = wsService
  }

  func preparePrivateSession() async throws {
    let code = try await getNewSessionCode()
    telemetry.event("session.invite_created")
    await wsService.setupPrivateSession(code)
  }

  func getNewSessionCode() async throws -> String {
#if DEBUG
    if AppBuildInfo.isXcodePreview { return "PREVIEW1AB" }
#endif

    guard let url = URL(string: AppEnvironment.createSessionUrl) else {
      throw SessionError.invalidURL
    }

#if DEBUG
    let session = URLSession(
      configuration: .default,
      delegate: InsecureSession(),
      delegateQueue: nil,
    )
    let (data, response) = try await session.data(from: url)
#else
    let (data, response) = try await URLSession.shared.data(from: url)
#endif

    guard
      let httpResponse = response as? HTTPURLResponse,
      (200...299).contains(httpResponse.statusCode)
    else {
      throw SessionError.serverError
    }

    let decoded = try JSONDecoder().decode(CreateSessionResponse.self, from: data)
    // TODO: Remove this log before release.
    log.debug("Private session code received successfully with: \(decoded.code)")
    return decoded.code
  }

  static func sanitizeSessionCode(_ code: String) -> String {
    let allowed = CharacterSet.alphanumerics
    let scalars = code.unicodeScalars.filter { allowed.contains($0) }
    return String(String.UnicodeScalarView(scalars))
  }

  /// Invite URL → its code.
  static func sessionCode(fromURL urlString: String) -> String? {
    guard
      let code = AppEnvironment.privateSessionCode(from: urlString),
      isValidSessionCode(code)
    else { return nil }
    return code
  }

  /// Typed or pasted input → its code, accepting a bare code or an invite URL.
  static func sessionCode(fromPayload payload: String) -> String? {
    let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if isValidSessionCode(trimmed) { return trimmed }
    return sessionCode(fromURL: trimmed)
  }

  static func isValidSessionCode(_ code: String) -> Bool {
    let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count == 10 else { return false }
    return trimmed.allSatisfy { $0.isLetter || $0.isNumber }
  }
}

enum SessionError: LocalizedError {
  case invalidURL
  case serverError
  var errorDescription: String? {
    switch self {
    case .invalidURL: return "Invalid session URL"
    case .serverError: return "Failed to create session"
    }
  }
}
