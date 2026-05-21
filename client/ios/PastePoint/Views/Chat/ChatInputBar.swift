//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Logging
import SwiftUI

struct ChatInputBar: View {
  private let logger = Logger(label: "ChatInputBar")
  let onSend: (String) -> Bool

  @State private var message = ""

  private var trimmed: String {
    message.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    VStack(spacing: 10) {

      TextField("Type your message", text: $message, axis: .vertical)
        .lineLimit(1...5)
        .textFieldStyle(.plain)
        .font(.body)
        .foregroundStyle(.textPrimary)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)

      HStack(alignment: .center) {

        // TODO: Implement attachment picker; add toast = .error("...") on failure
        Button {
          logger.info("Attachments Button Clicked")
        } label: {
          Image("link")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 18, height: 18)
        }
        .foregroundStyle(.textSecondary)
        .buttonStyle(.plain)

        Spacer()

        Button {
          handleSubmit()
        } label: {
          HStack(spacing: 8) {
            Text("Send")
              .font(.headline)
              .fontWeight(.bold)

            Image("send")
              .renderingMode(.template)
              .resizable()
              .scaledToFit()
              .frame(width: 16, height: 16)
          }
          .foregroundStyle(.white)
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
          .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .fill(.brand),
          )
        }
        .buttonStyle(.plain)
        .disabled(trimmed.isEmpty)
        .opacity(trimmed.isEmpty ? 0.6 : 1)
      }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
    .background(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(.inputBackground),
    )
  }

  private func handleSubmit() {
    guard !trimmed.isEmpty else { return }
    if onSend(trimmed) {
      logger.info("send message successfully")
      message = ""
    } else {
      logger.error("send message failed")
    }
  }
}

// MARK: - Preview

#if DEBUG
#Preview {
  ChatInputBar { _ in true }
}
#endif
