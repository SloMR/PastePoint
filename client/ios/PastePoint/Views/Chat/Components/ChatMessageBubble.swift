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
  let fileTransfer: FileTransferData?
  let onAccept: (() -> Void)?
  let onDecline: (() -> Void)?

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

        if let transfer = fileTransfer {
          attachmentBody(transfer: transfer)
        } else {
          textBody
        }
      }

      if alignment == .trailing {
        avatar
      } else {
        Spacer(minLength: 30)
      }
    }
    .frame(maxWidth: .infinity)
  }

  private var avatar: some View {
    Image("group")
      .resizable()
      .scaledToFit()
      .frame(width: 32, height: 32)
  }

  private var textBody: some View {
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

  private func attachmentBody(transfer: FileTransferData) -> some View {
    VStack(alignment: .leading, spacing: 8) {
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

      if transfer.status == .pending, onAccept != nil, onDecline != nil {
        HStack(spacing: 8) {
          Button("Accept") {
            onAccept?()
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
          Button("Decline", role: .destructive) {
            onDecline?()
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }
      } else if alignment == .leading {
        if transfer.status == .completed {
          Label(
            transfer.fileURL == nil ? "Saved to Photos" : "Saved to Files",
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
    .foregroundStyle(alignment == .trailing ? .textPrimary : .white)
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .frame(maxWidth: 260, alignment: .leading)
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

  private func statusLabel(_ status: FileTransferStatus) -> String {
    switch status {
    case .pending: return "Pending..."
    case .accepted: return "Receiving..."
    case .completed: return "Completed"
    case .declined: return "Declined"
    case .cancelled: return "Cancelled"
    case .failed: return "Failed"
    }
  }

  private func outgoingStatusLabel(_ transfer: FileTransferData) -> String {
    let delivered = transfer.deliveredCount ?? 0
    let total = transfer.recipientCount ?? 0
    switch transfer.status {
    case .completed:
      return delivered >= total ? "Sent" : "Sent to \(delivered) of \(total)"
    case .failed, .cancelled:
      return "Not delivered"
    default:
      return "Sending…"
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
