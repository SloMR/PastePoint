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
      title: .connectingTitle,
      message: .connectingDesc,
      onDismiss: onDismiss,
    ) {
      PulsingDot(color: AppColors.Status.warning)
    }
  }
}

#if DEBUG
#Preview {
  PreviewStage(alignment: .top) {
    ChatConnectionWarningBanner {}
  }
}
#endif
