//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation

/// First-launch terms acceptance. Bumping `currentVersion` re-gates everyone.
enum LegalConsent {
  static let storageKey = "legal.acceptedVersion"
  static let currentVersion = 1
}
