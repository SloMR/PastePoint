//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Combine
import Foundation
import Logging

struct CreateSessionResponse: Decodable {
  let code: String
}

@MainActor
final class SessionService: ObservableObject {
  private let logger = Logger(label: "Session")

  func getNewSessionCode() async throws -> String {
#if DEBUG
    if AppBuildInfo.isXcodePreview { return "PREVIEW1AB" }
#endif

    guard let url = URL(string: "https://\(AppEnvironment.apiUrl)/create-session") else {
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
    logger.debug("Private session code received successfully with: \(decoded.code)")
    return decoded.code
  }

  static func sanitizeSessionCode(_ code: String) -> String {
    let allowed = CharacterSet.alphanumerics
    let scalars = code.unicodeScalars.filter { allowed.contains($0) }
    return String(String.UnicodeScalarView(scalars))
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
