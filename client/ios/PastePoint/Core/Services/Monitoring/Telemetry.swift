//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation
import Sentry

nonisolated let telemetry = Telemetry()
typealias TelemetrySpan = any Span

struct Telemetry: Sendable {
  typealias Attributes = [String: any Sendable]

  enum Level: Sendable {
    case info
    case warning
    case error

    nonisolated var sentryLevel: SentryLevel {
      switch self {
      case .info: .info
      case .warning: .warning
      case .error: .error
      }
    }
  }

  /// Starts a detached root span in its own trace. Must be concluded with `endSpan`.
  nonisolated func startSpan(op: String, attributes: Attributes = [:], name: String? = nil) -> TelemetrySpan {
    let span = SentrySDK.startTransaction(name: name ?? op, operation: op, bindToScope: false)
    setAttributes(attributes, on: span)
    return span
  }

  /// Runs `work` inside a span in its own trace; the span ends when it settles.
  func withSpan<T>(
    op: String,
    isolation: isolated (any Actor)? = #isolation,
    work: (TelemetrySpan) async throws -> T,
  ) async rethrows -> T {
    let span = startSpan(op: op)
    do {
      let result = try await work(span)
      if !span.isFinished { span.finish(status: span.status == .undefined ? .ok : span.status) }
      return result
    } catch {
      if !span.isFinished { span.finish(status: .unknownError) }
      throw error
    }
  }

  /// Adds data attributes to a span; no-op for `nil`.
  nonisolated func setAttributes(_ attributes: Attributes, on span: TelemetrySpan?) {
    guard let span else { return }
    for (key, value) in attributes {
      span.setData(value: value, key: key)
    }
  }

  /// Records how a span concluded without ending it.
  nonisolated func markSpan(
    _ span: TelemetrySpan?,
    ok: Bool,
    outcome: String? = nil,
    message: String? = nil,
    attributes: Attributes = [:],
  ) {
    guard let span else { return }
    setAttributes(attributes, on: span)
    if let outcome { span.setData(value: outcome, key: "outcome") }
    if let message { span.setData(value: message, key: "message") }
    span.status = Self.status(ok: ok, outcome: outcome)
  }

  /// Records the outcome and finishes the span.
  nonisolated func endSpan(
    _ span: TelemetrySpan?,
    ok: Bool,
    outcome: String? = nil,
    message: String? = nil,
    attributes: Attributes = [:],
  ) {
    guard let span else { return }
    markSpan(span, ok: ok, outcome: outcome, message: message, attributes: attributes)
    span.finish(status: span.status)
  }

  /// Countable product event — counts/sizes/kinds only, never content.
  nonisolated func event(_ message: String, attributes: Attributes = [:]) {
    guard SentrySDK.isEnabled else { return }
    SentrySDK.logger.info(message, attributes: attributes)
  }

  /// Countable anomaly event (warn); same rules as `event`.
  nonisolated func warnEvent(_ message: String, attributes: Attributes = [:]) {
    guard SentrySDK.isEnabled else { return }
    SentrySDK.logger.warn(message, attributes: attributes)
  }

  /// Reports a log-level error as an Issue, keeping the current breadcrumbs.
  nonisolated func captureError(_ message: String) {
    guard SentrySDK.isEnabled else { return }
    SentrySDK.capture(message: message) { scope in
      scope.setLevel(.error)
    }
  }

  nonisolated func breadcrumb(category: String, message: String, level: Level = .info, data: Attributes = [:]) {
    let crumb = Breadcrumb(level: level.sentryLevel, category: category)
    crumb.message = message
    for (key, value) in data {
      crumb.setData(value: value, key: key)
    }
    SentrySDK.addBreadcrumb(crumb)
  }

  /// Picks a named span status from the outcome; `message` never affects it.
  private nonisolated static func status(ok: Bool, outcome: String?) -> SentrySpanStatus {
    if ok { return .ok }
    switch outcome {
    case "cancelled": return .cancelled
    case "timeout", "stalled": return .deadlineExceeded
    default: return .unknownError
    }
  }
}
