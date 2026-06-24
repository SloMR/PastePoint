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
      title: "Local network access is off",
      message: "PastePoint needs it to find people nearby.",
      actionTitle: "Open Settings",
      onAction: openSettings,
      onDismiss: onDismiss,
      leading: {
        Image(systemName: "wifi.slash")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(AppColors.Status.danger)
      },
    )
  }

  private func openSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
  }
}

#if DEBUG
#Preview {
  NetworkPermissionBanner {}
    .frame(maxHeight: .infinity, alignment: .top)
    .background(AppColors.Background.background)
}
#endif
