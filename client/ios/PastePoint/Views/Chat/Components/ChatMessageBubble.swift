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
  @Environment(\.isIPad) private var isIPad
  @State private var previewImage: UIImage?
  @State private var previewRevealed = false

  let alignment: MessageAlignment
  let name: String
  let avatarName: String
  let time: String
  let text: String
  let fileTransfer: FileTransferData?
  let onAccept: (() -> Void)?
  let onDecline: (() -> Void)?
  var onBlock: (() -> Void)?
  var onReport: (() -> Void)?

  private var bubbleMaxWidth: CGFloat {
    isIPad ? 280 : 260
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

        Group {
          if let transfer = fileTransfer {
            attachmentBody(transfer: transfer)
          } else {
            textBody
          }
        }
        .contextMenu { bubbleMenu }
      }

      if alignment == .trailing {
        avatar
      } else {
        Spacer(minLength: 30)
      }
    }
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder
  private var bubbleMenu: some View {
    if fileTransfer == nil {
      Button {
        UIPasteboard.general.string = text
      } label: {
        Label(String(localized: .copy), systemImage: "doc.on.doc")
      }
    }

    if let onBlock {
      Button(role: .destructive, action: onBlock) {
        Label(String(localized: .blockUser), systemImage: "hand.raised")
      }
    }

    if let onReport {
      Button(role: .destructive, action: onReport) {
        Label(String(localized: .reportAndBlock), systemImage: "flag")
      }
    }
  }

  private var avatar: some View {
    Image(avatarName)
      .resizable()
      .scaledToFit()
      .frame(width: 32, height: 32)
      .clipShape(Circle())
  }

  private var textBody: some View {
    Text(text)
      .font(.callout)
      .foregroundStyle(alignment == .trailing ? .textPrimary : .white)
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .frame(maxWidth: bubbleMaxWidth, minHeight: 60, alignment: .leading)
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

  private var shouldBlurPreview: Bool {
    alignment == .leading && previewImage != nil && !previewRevealed
  }

  private var previewSlot: some View {
    Group {
      if let previewImage {
        Image(uiImage: previewImage)
          .resizable()
          .scaledToFit()
      } else {
        Image(systemName: "doc")
          .resizable()
          .scaledToFit()
          .opacity(0.5)
          .padding(50)
      }
    }
    .blur(radius: shouldBlurPreview ? 18 : 0)
    .frame(maxWidth: bubbleMaxWidth - 24, maxHeight: 220)
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    .allowsHitTesting(false)
    .overlay {
      if shouldBlurPreview {
        Button {
          withAnimation(.easeOut(duration: 0.2)) { previewRevealed = true }
        } label: {
          VStack(spacing: 4) {
            Image(systemName: "eye.slash.fill")
              .font(.title3)
            Text(.tapToReveal)
              .font(.caption2)
              .fontWeight(.semibold)
          }
          .foregroundStyle(.white)
          .padding(10)
          .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
      }
    }
  }

  @ViewBuilder
  private func attachmentStatus(_ transfer: FileTransferData) -> some View {
    if transfer.status == .pending, onAccept != nil, onDecline != nil {
      HStack(spacing: 8) {
        Button(.accept) {
          onAccept?()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        Button(.decline, role: .destructive) {
          onDecline?()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
    } else if alignment == .leading {
      if transfer.status == .completed {
        Label(
          transfer.fileURL == nil ? .savedToPhotos : .savedToFiles,
          systemImage: "checkmark.circle",
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
      } else {
        Text(statusLabel(transfer.status))
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    } else if alignment == .trailing {
      Text(outgoingStatusLabel(transfer))
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
  }

  private func attachmentBody(transfer: FileTransferData) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      previewSlot

      HStack(spacing: 8) {
        Image(systemName: "doc")
          .font(.title3)
          .foregroundStyle(alignment == .trailing ? .textPrimary : .white)
        VStack(alignment: .leading, spacing: 2) {
          Text(transfer.fileName)
            .font(.callout)
            .lineLimit(1)
            .truncationMode(.middle)
          Text(formatBytes(transfer.fileSize))
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }

      attachmentStatus(transfer)
    }
    .task(id: transfer.previewDataUrl) {
      let dataUrl = transfer.previewDataUrl
      let data = await Task.detached { Self.decodePreviewData(dataUrl) }.value
      previewImage = data.flatMap { UIImage(data: $0) }
      previewRevealed = false
    }
    .foregroundStyle(alignment == .trailing ? .textPrimary : .white)
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
    .background(
      UnevenRoundedRectangle(
        topLeadingRadius: alignment == .trailing ? 16 : 4,
        bottomLeadingRadius: 16,
        bottomTrailingRadius: 16,
        topTrailingRadius: alignment == .trailing ? 4 : 16,
      )
      .fill(alignment == .trailing ? .inputBackground : .brand),
    )
  }

  private func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }

  private nonisolated static func decodePreviewData(_ dataUrl: String?) -> Data? {
    guard
      let dataUrl,
      let comma = dataUrl.firstIndex(of: ","),
      let data = Data(base64Encoded: String(dataUrl[dataUrl.index(after: comma)...]))
    else {
      return nil
    }

    return data
  }

  private func statusLabel(_ status: FileTransferStatus) -> LocalizedStringResource {
    switch status {
    case .pending: return .fileStatusPending
    case .accepted: return .fileStatusReceiving
    case .completed: return .fileStatusCompleted
    case .declined: return .declined
    case .cancelled: return .cancelled
    case .failed: return .fileStatusFailed
    }
  }

  private func outgoingStatusLabel(_ transfer: FileTransferData) -> LocalizedStringResource {
    let delivered = transfer.deliveredCount ?? 0
    let total = transfer.recipientCount ?? 0
    switch transfer.status {
    case .completed:
      return delivered >= total ? .fileSendDelivered : .fileSendPartial(delivered, total)
    case .failed, .cancelled:
      return .fileSendNone
    default:
      return .fileSendSending
    }
  }
}

// MARK: - Preview

#if DEBUG
#Preview {
  PreviewStage {
    VStack(spacing: 12) {
      ChatMessageBubble(
        alignment: .leading,
        name: "Garry Schulist",
        avatarName: ChatAvatar.imageName(for: "Garry Schulist", isMine: false),
        time: "9:04 PM",
        text: "Hello",
        fileTransfer: FileTransferData(
          fileId: "preview-id",
          fileName: "report.pdf",
          fileSize: 4_127_524,
          fromUser: "Garry Schulist",
          status: .pending,
          fileURL: nil,
        ),
        onAccept: { },
        onDecline: { },
      )

      ChatMessageBubble(
        alignment: .trailing,
        name: "Gwen Kuphal",
        avatarName: ChatAvatar.imageName(for: "Gwen Kuphal", isMine: true),
        time: "9:05 PM",
        text: "Hi",
        fileTransfer: nil,
        onAccept: nil,
        onDecline: nil,
      )
    }
    .padding()
  }
}
#endif
