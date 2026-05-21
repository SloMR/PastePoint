//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct ChatContainerView: View {
  let messages: [ChatMessage]

  var body: some View {
    Group {
      if messages.isEmpty {
        WelcomeView()
      } else {
        ChatView(messages: messages)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(AppColors.Background.background)
  }
}
