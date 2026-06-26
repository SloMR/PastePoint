//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct SettingsMembersSection: View {
  @EnvironmentObject private var services: AppServices

  var body: some View {
    VStack {
      HStack(alignment: .center, spacing: 0) {
        Image("users")
          .renderingMode(.template)
          .resizable()
          .scaledToFit()
          .frame(width: 16, height: 16)
          .padding(.trailing, 5)

        Text(.members)
          .font(.subheadline)
          .foregroundColor(.textPrimary)

        Spacer()

        Text(.onlineMembersCount(services.roomService.members.filter { $0 != services.userService.user }.count))
          .font(.caption2)
          .foregroundColor(.textPrimary)
      }
      .padding(.horizontal)

      Group {
        let others = services.roomService.members.filter { $0 != services.userService.user }
        if others.isEmpty {
          Text(.noMembersOnline)
            .font(.subheadline)
            .foregroundColor(.textPrimary)
            .fontWeight(.bold)
        } else {
          ForEach(others, id: \.self) { member in
            let isConnected = services.signalingService.connectedPeers.contains(member)
            let uploads = services.fileTransferService.activeUploads.filter { $0.targetUser == member }
            let downloads = services.fileTransferService.activeDownloads.filter { $0.fromUser == member }
            let dotColor: Color = {
              if services.signalingService.connectedPeers.contains(member) { return .green }
              if services.signalingService.connectingPeers.contains(member) { return .yellow }
              return .red
            }()

            VStack(alignment: .leading, spacing: 6) {
              HStack(alignment: .center, spacing: 0) {
                Circle()
                  .fill(dotColor)
                  .frame(width: 14, height: 14)
                  .padding(.trailing, 6)

                Text(member)
                  .font(.subheadline)
                  .foregroundColor(.textPrimary)

                Spacer()

                AttachmentMenu { staged in
                  await services.fileTransferService.sendFiles(staged, to: member)
                } content: {
                  Image("link")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .padding(.trailing, 5)
                    .foregroundStyle(.textSecondary)
                }
                .disabled(!isConnected)
                .opacity(isConnected ? 1 : 0.3)
              }
              .animation(.easeInOut(duration: 0.2), value: dotColor)

              if !uploads.isEmpty || !downloads.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                  ForEach(uploads) { upload in
                    transferRow(
                      direction: .up,
                      name: upload.displayName,
                      progress: upload.progress,
                      phase: upload.phase,
                    ) {
                      services.fileTransferService.stopFileUpload(targetUser: member, fileId: upload.id)
                    }
                  }
                  ForEach(downloads) { download in
                    transferRow(
                      direction: .down,
                      name: download.fileName,
                      progress: download.progress,
                      phase: nil,
                    ) {
                      services.fileTransferService.cancelFileDownload(fromUser: member, fileId: download.id)
                    }
                  }
                }
                .padding(.leading, 20)
              }
            }
          }
        }
      }
      .padding(.horizontal)
      .padding(.top, 22)
    }
    .padding(.top, 12)
  }

  private enum TransferDirection {
    case up
    case down
  }

  @ViewBuilder
  private func transferRow(
    direction: TransferDirection,
    name: String,
    progress: Double,
    phase: FileUpload.Phase?,
    onCancel: @escaping () -> Void,
  ) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 6) {
        Image(systemName: direction == .up ? "arrow.up" : "arrow.down")
          .font(.caption2)
          .foregroundStyle(.textSecondary)

        Text(name)
          .font(.caption)
          .lineLimit(1)
          .truncationMode(.middle)
          .foregroundStyle(.textPrimary)
        Spacer()
        Text(progressLabel(progress: progress, phase: phase))
          .font(.caption2)
          .foregroundStyle(.textSecondary)
        Button {
          onCancel()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.caption)
            .foregroundStyle(.textSecondary)
        }
        .buttonStyle(.plain)
      }
      ProgressView(value: max(0, min(1, progress)))
        .progressViewStyle(.linear)
        .tint(.brand)
        .scaleEffect(x: 1, y: 0.6, anchor: .center)
    }
  }

  private func progressLabel(progress: Double, phase: FileUpload.Phase?) -> String {
    if phase == .finalizing { return String(localized: .finalizingTransfer) }
    return progress.formatted(.percent.precision(.fractionLength(0)))
  }
}
