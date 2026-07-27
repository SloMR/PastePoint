//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct WelcomeInviteCard: View {
  let onShareInvite: () -> Void

  var body: some View {
    WelcomeCard(title: .inviteTheOtherDevice, message: .inviteShareBody) {
      Button(action: onShareInvite) {
        HStack(spacing: 8) {
          Image("qrcode")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
          Text(.shareInvite)
        }
      }
      .buttonStyle(.pill(tint: AppColors.Brand.brand))
      .padding(.top, 2)
    }
  }
}

// MARK: - Preview

#if DEBUG
#Preview {
  PreviewStage {
    WelcomeInviteCard {}
      .padding()
  }
}
#endif
