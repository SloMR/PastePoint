//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct NetworkPermissionBanner: View {
  var onDismiss: () -> Void

  var body: some View {
    StatusBanner(
      tint: AppColors.Status.danger,
      title: .localNetworkOffTitle,
      message: .localNetworkOffDesc,
      actionTitle: .openSettings,
      onAction: openSettings,
      onDismiss: onDismiss,
    ) {
      Image(systemName: "wifi.slash")
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(AppColors.Status.danger)
    }
  }

  private func openSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
  }
}

#if DEBUG
#Preview {
  PreviewStage(alignment: .top) {
    NetworkPermissionBanner {}
  }
}
#endif
