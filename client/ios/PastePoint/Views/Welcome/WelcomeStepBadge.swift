//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct WelcomeStepBadge: View {
  let number: Int

  var body: some View {
    Text("\(number)")
      .font(.caption)
      .fontWeight(.semibold)
      .foregroundStyle(.white)
      .frame(width: 26, height: 26)
      .background(.brand)
      .clipShape(Circle())
  }
}

// MARK: - Preview

#if DEBUG
#Preview {
  PreviewStage {
    HStack(spacing: 12) {
      WelcomeStepBadge(number: 1)
      WelcomeStepBadge(number: 2)
      WelcomeStepBadge(number: 3)
    }
  }
}
#endif
