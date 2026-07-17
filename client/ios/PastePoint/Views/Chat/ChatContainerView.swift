//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct ChatContainerView: View {
  let messages: [ChatMessage]
  let onAcceptFile: (_ fromUser: String, _ fileId: String) -> Void
  let onDeclineFile: (_ fromUser: String, _ fileId: String) -> Void
  let onBlock: (String) -> Void
  let onReport: (ChatMessage) -> Void

  var body: some View {
    Group {
      if messages.isEmpty {
        WelcomeView()
      } else {
        ChatView(
          messages: messages,
          onAcceptFile: onAcceptFile,
          onDeclineFile: onDeclineFile,
          onBlock: onBlock,
          onReport: onReport,
        )
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(AppColors.Background.background)
  }
}
