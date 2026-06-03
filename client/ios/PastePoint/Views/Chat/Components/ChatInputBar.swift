//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Logging
import SwiftUI

struct ChatInputBar: View {
  private let logger = Logger(label: "ChatInputBar")
  let onSend: (String) -> Bool
  let onSendFiles: ([StagedFile]) -> Bool
  let hasConnectedPeers: Bool

  @State private var message = ""
  @State private var stagedFiles: [StagedFile] = []

  private var trimmed: String {
    message.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    VStack(spacing: 10) {

      if !stagedFiles.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(stagedFiles) { file in
              HStack(spacing: 6) {
                Image(systemName: "doc")
                  .font(.caption)
                Text(file.name)
                  .font(.caption)
                  .lineLimit(1)
                Button {
                  if let idx = stagedFiles.firstIndex(where: { $0.id == file.id }) {
                    let removed = stagedFiles.remove(at: idx)
                    try? FileManager.default.removeItem(at: removed.url)
                  }
                } label: {
                  Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                }
                .buttonStyle(.plain)
              }
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                  .fill(.textSecondary.opacity(0.15))
              }
            }
          }
        }
      }

      TextField("Type your message", text: $message, axis: .vertical)
        .lineLimit(1...5)
        .textFieldStyle(.plain)
        .font(.body)
        .foregroundStyle(.textPrimary)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)

      HStack(alignment: .center) {

        // TODO: Show toast on picker/stage failure (see logger.error sites)
        AttachmentMenu { staged in
          stagedFiles.append(contentsOf: staged)
        } content: {
          Image("link")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 18, height: 18)
        }
        .foregroundStyle(.textSecondary)
        .disabled(!hasConnectedPeers)
        .opacity(hasConnectedPeers ? 1 : 0.3)

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
        .disabled(trimmed.isEmpty && stagedFiles.isEmpty)
        .opacity((trimmed.isEmpty && stagedFiles.isEmpty) ? 0.6 : 1)
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
    let hasText = !trimmed.isEmpty
    let hasFiles = !stagedFiles.isEmpty
    guard hasText || hasFiles else { return }

    if hasText {
      if onSend(trimmed) {
        logger.info("send message successfully")
        message = ""
      } else {
        logger.error("send message failed")
      }
    }

    if hasFiles {
      if onSendFiles(stagedFiles) {
        // Ownership of tmp files transfers to FileUpload; do NOT delete here.
        logger.info("send files successfully")
        stagedFiles = []
      } else {
        logger.error("send files failed")
      }
    }
  }
}

// MARK: - Preview

#if DEBUG
#Preview {
  ChatInputBar(
    onSend: { _ in true },
    onSendFiles: { _ in true },
    hasConnectedPeers: true,
  )
}
#endif
