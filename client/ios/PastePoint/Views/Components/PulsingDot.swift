//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct PulsingDot: View {
  let color: Color

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var pulsing = false

  var body: some View {
    Circle()
      .fill(color)
      .frame(width: 9, height: 9)
      .scaleEffect(reduceMotion ? 1.0 : (pulsing ? 1.0 : 0.62))
      .opacity(reduceMotion ? 1.0 : (pulsing ? 1.0 : 0.45))
      .onAppear {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
          pulsing = true
        }
      }
      .accessibilityHidden(true)
  }
}

#if DEBUG
#Preview {
  PreviewStage {
    PulsingDot(color: AppColors.Status.warning)
      .frame(width: 22, height: 22)
  }
}
#endif
