//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Combine
import Foundation
import Logging

// MARK: - Wire model

/// One platform's policy from `GET /version`; we decode only `ios`.
private struct PlatformVersion: Decodable {
  let minimum: String
  let latest: String
  let url: String
}

private struct VersionResponse: Decodable {
  let ios: PlatformVersion
}

// MARK: - Recommendation

/// What the update UI should show. `.required` blocks; `.optional` nudges.
enum UpdateRecommendation {
  case required(url: URL)
  case optional(latest: String, url: URL)
}

// MARK: - Service

/// Launch-time version check; publishes `recommendation` for the gate/nudge.
@MainActor
final class AppUpdateService: ObservableObject {
  @Published private(set) var recommendation: UpdateRecommendation?

  private let logger = Logger(label: "AppUpdate")

  private var isChecking: Bool = false

  private static let lastOptionalPromptKey = "AppUpdate.lastOptionalPromptAt"
  private let optionalThrottle: TimeInterval = 12 * 60 * 60 // 12 hours

  /// Fetches the policy and recomputes `recommendation`. Fails open on error.
  func check() async {
#if DEBUG
    guard !AppBuildInfo.isXcodePreview else { return }
#endif

    guard !isChecking else { return }
    isChecking = true
    defer { isChecking = false }

    guard let url = URL(string: AppEnvironment.versionUrl) else {
      logger.error("Invalid version URL")
      return
    }

    let policy: PlatformVersion
    do {
      let data = try await fetch(url)
      policy = try JSONDecoder().decode(VersionResponse.self, from: data).ios
    } catch {
      logger.debug("Version check failed, ignoring: \(error.localizedDescription)")
      return
    }

    recommendation = evaluate(policy)
  }

  /// Clears an active `.optional` nudge; no-op for `.required`.
  func dismissOptional() {
    if case .optional = recommendation { recommendation = nil }
  }
}

private extension AppUpdateService {
  func fetch(_ url: URL) async throws -> Data {
#if DEBUG
    let session = URLSession(configuration: .default, delegate: InsecureSession(), delegateQueue: nil)
#else
    let session = URLSession.shared
#endif

    let (data, response) = try await session.data(from: url)
    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
      throw URLError(.badServerResponse)
    }
    return data
  }

  func evaluate(_ policy: PlatformVersion) -> UpdateRecommendation? {
    let installed = Bundle.main.appVersion

    guard !policy.url.isEmpty, let url = URL(string: policy.url) else {
      if !policy.minimum.isEmpty || !policy.latest.isEmpty {
        logger.warning("Version policy has no valid url; ignoring")
      }
      return recommendation
    }

    if isLower(installed, than: policy.minimum) {
      return .required(url: url) // force — never throttled
    }
    if isLower(installed, than: policy.latest) {
      guard shouldShowOptional() else { return nil }
      markOptionalShown()
      return .optional(latest: policy.latest, url: url)
    }

    return nil // up to date — clears the gate
  }

  func isLower(_ first: String, than second: String) -> Bool {
    guard !second.isEmpty else { return false }
    return first.compare(second, options: .numeric) == .orderedAscending
  }

  func shouldShowOptional() -> Bool {
    let last = UserDefaults.standard.object(forKey: Self.lastOptionalPromptKey) as? Date
    guard let last else { return true }
    return Date().timeIntervalSince(last) >= optionalThrottle
  }

  func markOptionalShown() {
    UserDefaults.standard.set(Date(), forKey: Self.lastOptionalPromptKey)
  }
}
