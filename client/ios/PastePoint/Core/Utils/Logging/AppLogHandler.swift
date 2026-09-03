//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation
import Logging
import os

struct AppLogHandler: LogHandler {
  private let label: String
  var metadata: Logging.Logger.Metadata = [:]

#if DEBUG
  private let osLogger: os.Logger
  private let isPreview: Bool
  var logLevel: Logging.Logger.Level = .debug
#else
  var logLevel: Logging.Logger.Level = .info
#endif

  init(label: String) {
    self.label = label
#if DEBUG
    osLogger = os.Logger(subsystem: "com.pastepoint", category: label)
    isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
#endif
  }

  subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
    get { metadata[key] }
    set { metadata[key] = newValue }
  }

  func log(event: Logging.LogEvent) {
#if DEBUG
    logToConsole(event)
#endif
    forwardToTelemetry(event)
  }

#if DEBUG
  private func logToConsole(_ event: Logging.LogEvent) {
    let filename = URL(fileURLWithPath: event.file).lastPathComponent
    let entry = "\(emoji(for: event.level)) \(filename):\(event.line) [\(event.function)]: \(event.message)"

    if isPreview {
      print(entry)
      return
    }

    switch event.level {
    case .trace, .debug:
      osLogger.debug("\(entry, privacy: .public)")
    case .info:
      osLogger.info("\(entry, privacy: .public)")
    case .notice:
      osLogger.notice("\(entry, privacy: .public)")
    case .warning:
      osLogger.warning("\(entry, privacy: .public)")
    case .error:
      osLogger.error("\(entry, privacy: .public)")
    case .critical:
      osLogger.critical("\(entry, privacy: .public)")
    }
  }

  private func emoji(for level: Logging.Logger.Level) -> String {
    switch level {
    case .trace: return "⚪️"
    case .debug: return "🔵"
    case .info: return "🟢"
    case .notice: return "🟡"
    case .warning: return "🟠"
    case .error: return "🔴"
    case .critical: return "🟣"
    }
  }
#endif

  private func forwardToTelemetry(_ event: Logging.LogEvent) {
    let message = "\(label) :: \(event.message)"
    switch event.level {
    case .trace, .debug:
      break
    case .info, .notice:
      telemetry.breadcrumb(category: "log", message: message)
    case .warning:
      telemetry.warnEvent(message)
      telemetry.breadcrumb(category: "log", message: message, level: .warning)
    case .error, .critical:
      telemetry.captureError(message)
    }
  }
}
