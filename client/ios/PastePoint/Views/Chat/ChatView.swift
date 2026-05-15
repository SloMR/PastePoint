//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct ChatView: View {
  @EnvironmentObject private var services: AppServices

  private var isPrivate: Bool {
    services.wsService.currentSessionCode != nil
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        // Room header row
        ChatRoomHeader(isPrivate: isPrivate)

        // Chat bubbles (merged from ChatView)
        VStack(spacing: 16) {
          ChatMessageBubble(
            alignment: .leading,
            name: "Garry Schulist",
            time: "9:04 PM",
            text: "Hello",
          )

          ChatMessageBubble(
            alignment: .trailing,
            name: "Gwen Kuphal",
            time: "9:05 PM",
            text: "Hi",
          )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 16)
      }
      .padding(.horizontal, 16)
    }
  }
}

// MARK: - Preview

#if DEBUG
#Preview {
  ChatView()
    .environmentObject(AppServices.preview)
}
#endif
