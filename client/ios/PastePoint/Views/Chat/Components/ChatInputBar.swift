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

  private var isSendDisabled: Bool {
    trimmed.isEmpty && stagedFiles.isEmpty
  }

  var body: some View {
    VStack(spacing: 8) {

      if !stagedFiles.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(stagedFiles) { file in
              ChatStagedFileTile(file: file) {
                removeStagedFile(file)
              }
            }
          }
          .padding(.horizontal, 4)
        }
      }

      HStack(alignment: .bottom, spacing: 8) {

        // TODO: Show toast on picker/stage failure (see logger.error sites)
        AttachmentMenu { staged in
          stagedFiles.append(contentsOf: staged)
        } content: {
          Image("link")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
            .frame(width: 22, height: 32)
        }
        .foregroundStyle(.textSecondary)
        .disabled(!hasConnectedPeers)
        .opacity(hasConnectedPeers ? 1 : 0.3)

        TextField("Type your message", text: $message, axis: .vertical)
          .lineLimit(1...5)
          .textFieldStyle(.plain)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled(true)
          .font(.subheadline)
          .foregroundStyle(.textPrimary)
          .padding(.horizontal, 14)
          .padding(.vertical, 5)
          .frame(maxWidth: .infinity)
          .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
              .fill(.inputBackground),
          )

        Button {
          handleSubmit()
        } label: {
          Image("send")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 18, height: 18)
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(
              Circle()
                .fill(.brand),
            )
            .frame(width: 30, height: 32)
        }
        .buttonStyle(.plain)
        .disabled(isSendDisabled)
        .opacity(isSendDisabled ? 0.6 : 1)
      }
    }
    .padding(.horizontal, 4)
    .padding(.top, 8)
    .padding(.bottom, 6)
  }

  private func removeStagedFile(_ file: StagedFile) {
    guard let idx = stagedFiles.firstIndex(where: { $0.id == file.id }) else { return }
    let removed = stagedFiles.remove(at: idx)
    removed.kind.releaseSource(at: removed.url)
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
extension ChatInputBar {
  init(
    onSend: @escaping (String) -> Bool,
    onSendFiles: @escaping ([StagedFile]) -> Bool,
    hasConnectedPeers: Bool,
    stagedFiles: [StagedFile],
  ) {
    self.onSend = onSend
    self.onSendFiles = onSendFiles
    self.hasConnectedPeers = hasConnectedPeers
    self._stagedFiles = State(initialValue: stagedFiles)
  }
}

#Preview {
  ChatInputBar(
    onSend: { _ in true },
    onSendFiles: { _ in true },
    hasConnectedPeers: true,
    stagedFiles: [
      StagedFile(
        id: UUID(),
        name: "Quarterly-Report.pdf",
        size: 248_000,
        url: URL(fileURLWithPath: "/dev/null"),
        kind: .ownedTemp,
      ),
      StagedFile(
        id: UUID(),
        name: "Photo-2026-06-20.heic",
        size: 1_900_000,
        url: URL(fileURLWithPath: "/dev/null"),
        kind: .ownedTemp,
      ),
      StagedFile(
        id: UUID(),
        name: "archive.zip",
        size: 5_400_000,
        url: URL(fileURLWithPath: "/dev/null"),
        kind: .ownedTemp,
      ),
    ],
  )
  .frame(maxHeight: .infinity, alignment: .bottom)
}
#endif
