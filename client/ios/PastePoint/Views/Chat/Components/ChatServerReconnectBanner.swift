//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct ChatServerReconnectBanner: View {
  let attempt: Int
  let nextAttemptDate: Date

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let remaining = max(0, Int(nextAttemptDate.timeIntervalSince(context.date).rounded(.up)))
      StatusBanner(
        tint: AppColors.Status.info,
        title: .serverReconnectTitle,
        message: remaining > 0
          ? .serverReconnectCountdown(remaining, attempt)
          : .serverReconnectNow(attempt),
      ) {
        PulsingDot(color: AppColors.Status.info)
      }
    }
  }
}

#if DEBUG
#Preview {
  PreviewStage(alignment: .top) {
    ChatServerReconnectBanner(attempt: 2, nextAttemptDate: Date().addingTimeInterval(8))
  }
}
#endif
