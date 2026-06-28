//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation
import Logging

// MARK: - Version

extension Bundle {
  var appVersion: String {
    infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
  }
}

// MARK: - Build Environment

enum AppBuildInfo {
  /// `true` when running inside Xcode's SwiftUI preview renderer (simulator or in-process).
  static let isXcodePreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
}

// MARK: - Logging Bootstrap

enum AppLogging {
  private static let once: Void = {
#if DEBUG
    LoggingSystem.bootstrap(AppLogHandler.init)
#else
    LoggingSystem.bootstrap(SwiftLogNoOpLogHandler.init)
#endif
  }()

  /// Bootstraps the logging system exactly once per process. Thread-safe.
  static func bootstrap() { _ = once }
}
