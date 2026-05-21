//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

enum MessageAlignment {
  case leading // Incoming messages (left in LTR, right in RTL)
  case trailing // Outgoing messages (right in LTR, left in RTL)
}

struct ChatMessageBubble: View {
  let alignment: MessageAlignment
  let name: String
  let time: String
  let text: String

  private var avatar: some View {
    Image("group")
      .resizable()
      .scaledToFit()
      .frame(width: 32, height: 32)
  }

  var body: some View {
    HStack(alignment: .top, spacing: 10) {

      if alignment == .leading {
        avatar
      } else {
        Spacer(minLength: 30)
      }

      VStack(alignment: alignment == .leading ? .leading : .trailing, spacing: 6) {

        HStack(spacing: 6) {
          if alignment == .leading {
            Text(name)
              .font(.caption)
              .fontWeight(.semibold)
              .foregroundStyle(.textPrimary)

            Text(time)
              .font(.caption2)
              .foregroundStyle(.textSecondary)
          } else {
            Text(time)
              .font(.caption2)
              .foregroundStyle(.textSecondary)

            Text(name)
              .font(.caption)
              .fontWeight(.semibold)
              .foregroundStyle(.textPrimary)
          }
        }

        Text(text)
          .font(.callout)
          .foregroundStyle(alignment == .trailing ? .textPrimary : .white)
          .padding(.horizontal, 12)
          .padding(.vertical, 10)
          .frame(maxWidth: 260, minHeight: 60, alignment: .leading)
          .shadow(color: Color.black.opacity(0.06), radius: 1, x: 0, y: 1)
          .background(
            UnevenRoundedRectangle(
              topLeadingRadius: alignment == .trailing ? 16 : 4,
              bottomLeadingRadius: 16,
              bottomTrailingRadius: 16,
              topTrailingRadius: alignment == .trailing ? 4 : 16,
            )
            .fill(alignment == .trailing ? .inputBackground : .brand),
          )
          .fixedSize(horizontal: false, vertical: true)
      }

      if alignment == .trailing {
        avatar
      } else {
        Spacer(minLength: 30)
      }
    }
    .frame(maxWidth: .infinity)
  }
}

// MARK: - Preview

#if DEBUG
#Preview {
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
#endif
