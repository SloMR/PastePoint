//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct ChatInputBar: View {
  @Environment(\.layoutDirection) private var layoutDirection
  @EnvironmentObject private var toast: ToastCenter

  let onSend: (String) -> Bool
  let onSendFiles: ([StagedFile]) -> Bool
  let hasConnectedPeers: Bool

  var prewarmHash: (StagedFile) async -> Void = { _ in }

  @State private var message = ""
  @State private var stagedFiles: [StagedFile] = []

  private var trimmed: String {
    message.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var anyHashing: Bool {
    stagedFiles.contains { $0.hashing }
  }

  private var isSendDisabled: Bool {
    (trimmed.isEmpty && stagedFiles.isEmpty) || anyHashing
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

        // TODO: Show toast on picker/stage failure (see log.error sites)
        AttachmentMenu { staged in
          let marked = staged.map { file -> StagedFile in
            var copy = file
            copy.hashing = true
            return copy
          }
          stagedFiles.append(contentsOf: marked)
          for file in marked { startHashing(file) }
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
        .accessibilityLabel(Text(.attachFiles))

        TextField(String(localized: .typeYourMessage), text: $message, axis: .vertical)
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
            .scaleEffect(x: layoutDirection == .rightToLeft ? -1 : 1, y: 1)
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(
              Circle()
                .fill(.brand),
            )
            .frame(width: 30, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSendDisabled)
        .opacity(isSendDisabled ? 0.6 : 1)
        .accessibilityLabel(Text(.send))
      }
    }
    .padding(.horizontal, 4)
    .padding(.top, 8)
    .padding(.bottom, 6)
  }

  private func startHashing(_ file: StagedFile) {
    Task {
      await prewarmHash(file)
      if let idx = stagedFiles.firstIndex(where: { $0.id == file.id }) {
        stagedFiles[idx].hashing = false
      }
    }
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

    if anyHashing {
      toast.show(.info(.verifyingFilesWait))
      return
    }

    if hasText {
      if onSend(trimmed) {
        log.info("send message successfully")
        message = ""
      } else {
        log.error("send message failed")
      }
    }

    if hasFiles {
      if onSendFiles(stagedFiles) {
        // Ownership of tmp files transfers to FileUpload; do NOT delete here.
        log.info("send files successfully")
        stagedFiles = []
      } else {
        log.error("send files failed")
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
  PreviewStage(alignment: .bottom) {
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
  }
}
#endif
