//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct WelcomeHeader: View {
  let isPrivate: Bool
  let isAlone: Bool

  var body: some View {
    VStack(spacing: 20) {
      Image(isPrivate ? "lock.light" : "users")
        .resizable()
        .scaledToFit()
        .frame(width: 28, height: 28)
        .padding(18)
        .background(Circle().fill(.brand))
        .accessibilityHidden(true)

      VStack(spacing: 6) {
        Text(.emptyStateTitle)
          .font(.title2)
          .fontWeight(.bold)
          .foregroundStyle(.textPrimary)
          .multilineTextAlignment(.center)

        Text(isAlone ? .emptyStateAlone : .emptyStateConnected)
          .font(.subheadline)
          .foregroundStyle(.textSecondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 16)
      }
    }
  }
}

// MARK: - Preview

#if DEBUG
#Preview {
  PreviewStage {
    VStack(spacing: 32) {
      WelcomeHeader(isPrivate: false, isAlone: true)
      WelcomeHeader(isPrivate: true, isAlone: false)
    }
  }
}
#endif
