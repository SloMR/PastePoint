//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

#if DEBUG
import SwiftUI

/// Shared backdrop for component previews: fills the canvas with the app
/// background and anchors the content. Use `.bottom` for the input bar,
/// `.top` for nav/header bars, default (`.center`) for standalone pieces.
struct PreviewStage<Content: View>: View {
  var alignment: Alignment = .center
  @ViewBuilder var content: () -> Content

  var body: some View {
    content()
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
      .background(AppColors.Background.background)
  }
}
#endif
