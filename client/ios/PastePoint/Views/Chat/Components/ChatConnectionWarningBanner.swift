//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct ChatConnectionWarningBanner: View {
  var onDismiss: () -> Void

  var body: some View {
    StatusBanner(
      tint: AppColors.Status.warning,
      title: "Still connecting…",
      message: "Some members aren't reachable yet.",
      onDismiss: onDismiss,
      leading: {
        PulsingDot(color: AppColors.Status.warning)
      },
    )
  }
}

#if DEBUG
#Preview {
  ChatConnectionWarningBanner {}
    .frame(maxHeight: .infinity, alignment: .top)
    .background(AppColors.Background.background)
}
#endif
