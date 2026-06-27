//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct WelcomeStepList: View {
  let steps: [LocalizedStringResource]

  var body: some View {
    VStack(spacing: 8) {
      ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
        HStack(alignment: .center, spacing: 12) {
          WelcomeStepBadge(number: index + 1)
          Text(step)
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(.textPrimary)
            .multilineTextAlignment(.leading)
          Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(AppColors.Background.stepCard, in: RoundedRectangle(cornerRadius: 10))
      }
    }
    .frame(maxWidth: .infinity)
  }
}

// MARK: - Preview

#if DEBUG
#Preview {
  PreviewStage {
    WelcomeStepList(steps: [
      .inviteOthersPublic,
      .startConversation,
    ])
    .padding()
  }
}
#endif
