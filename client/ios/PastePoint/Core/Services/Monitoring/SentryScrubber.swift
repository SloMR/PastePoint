//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation
import Sentry

enum SentryScrubber {

  nonisolated static func anonymousUser() -> User {
    let user = User()
    user.ipAddress = "127.0.0.1"
    return user
  }

  /// Replaces the code in `/private/<code>` and `/ws/<code>` paths with `[code]`.
  nonisolated static func scrubSessionCodes(_ text: String) -> String {
    text.replacing(#/(/(?:private|ws)/)[A-Za-z0-9]+/#) { "\($0.output.1)[code]" }
  }

  /// Scrubs a breadcrumb's message and URL-like data fields.
  nonisolated static func scrub(_ breadcrumb: Breadcrumb) -> Breadcrumb {
    if let message = breadcrumb.message {
      breadcrumb.message = scrubSessionCodes(message)
    }
    for key in ["url", "from", "to"] {
      if let value = breadcrumb.data?[key] as? String {
        breadcrumb.setData(value: scrubSessionCodes(value), key: key)
      }
    }
    return breadcrumb
  }

  /// Strips identity, request details and locale from an event; transactions pass through here too.
  nonisolated static func scrub(_ event: Event) -> Event {
    event.user = anonymousUser()
    event.serverName = nil

    if let request = event.request {
      request.cookies = nil
      request.headers = nil
      request.queryString = nil
      if let url = request.url {
        request.url = scrubSessionCodes(url)
      }
    }

    if var context = event.context {
      context["device"]?.removeValue(forKey: "timezone")
      context["device"]?.removeValue(forKey: "locale")
      context.removeValue(forKey: "culture")
      context["app"]?.removeValue(forKey: "device_app_hash")
      event.context = context
    }
    return event
  }

  /// Drops the user attributes the SDK stamps on every log (its installation id).
  nonisolated static func scrub(_ entry: SentryLog) -> SentryLog {
    entry.body = scrubSessionCodes(entry.body)
    for key in ["user.id", "user.name", "user.email"] {
      entry.attributes.removeValue(forKey: key)
    }
    return entry
  }
}
