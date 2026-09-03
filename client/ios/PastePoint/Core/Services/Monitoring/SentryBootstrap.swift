//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation
import Sentry

enum SentryBootstrap {

  private enum Sampling {
    nonisolated static let traces: Double = 1.0
    nonisolated static let replaySession: Float = 0
    nonisolated static let replayOnError: Float = 0
  }

  private static var didStart = false

  static func start() {
    guard AppEnvironment.sentryEnabled, !AppEnvironment.sentryDSN.isEmpty, !didStart else { return }
    didStart = true
    SentrySDK.start(configureOptions: configure)
  }

  private nonisolated static func configure(_ options: Options) {
    options.dsn = AppEnvironment.sentryDSN
    options.environment = AppEnvironment.sentryEnvironment
    options.releaseName = "ios@\(Bundle.main.appVersion)"
    options.dist = Bundle.main.appBuild

    options.sendDefaultPii = false
    options.maxBreadcrumbs = 50
    options.attachScreenshot = false
    options.attachViewHierarchy = false

    options.tracesSampleRate = NSNumber(value: Sampling.traces)
    options.enableLogs = true
    options.sessionReplay.sessionSampleRate = Sampling.replaySession
    options.sessionReplay.onErrorSampleRate = Sampling.replayOnError

    options.enableAutoSessionTracking = false
    options.enableAppHangTracking = false
    options.enableAutoPerformanceTracing = false

    // SwiftUI view timing is off for now: SentrySwiftUI is linked but unused.
    // To turn it on, wrap a view in `SentryTracedView` (or `.sentryTrace("name")`).
    options.enableUIViewControllerTracing = false
    options.enableUserInteractionTracing = false
    options.enableFileIOTracing = false
    options.enableCoreDataTracing = false

    options.initialScope = { scope in
      scope.setUser(SentryScrubber.anonymousUser())
      return scope
    }
    options.beforeBreadcrumb = { SentryScrubber.scrub($0) }
    options.beforeSend = { SentryScrubber.scrub($0) }
    options.beforeSendLog = { SentryScrubber.scrub($0) }
  }
}
