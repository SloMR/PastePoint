//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Testing
@testable import PastePoint

@MainActor
struct AppBuildInfoTests {
  @Test
  func knowsItIsRunningTests() {
    #expect(AppBuildInfo.isRunningTests)
  }
}
