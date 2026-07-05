//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

extension EnvironmentValues {
  /// Regular width = iPad-style layout (full screen or a wide multitasking pane).
  /// Read via `@Environment(\.isIPad)`.
  var isIPad: Bool {
    horizontalSizeClass == .regular
  }
}
