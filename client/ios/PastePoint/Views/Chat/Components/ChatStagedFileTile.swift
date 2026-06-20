//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct ChatStagedFileTile: View {
  let file: StagedFile
  let onRemove: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: file.symbolName)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.brand)
        .frame(width: 26, height: 26)
        .background(
          Circle()
            .fill(.brand.opacity(0.15)),
        )

      VStack(alignment: .leading, spacing: 1) {
        Text(file.name)
          .font(.caption2)
          .lineLimit(1)
          .truncationMode(.middle)
          .foregroundStyle(.textPrimary)

        Text(file.sizeDescription)
          .font(.system(size: 10))
          .foregroundStyle(.textSecondary)
      }
      .frame(maxWidth: 120, alignment: .leading)

      Button(action: onRemove) {
        Image(systemName: "xmark")
          .font(.system(size: 8, weight: .bold))
          .foregroundStyle(.textPrimary)
          .frame(width: 16, height: 16)
          .background(Circle().fill(.textSecondary.opacity(0.25)))
      }
      .buttonStyle(.plain)
    }
    .padding(.leading, 6)
    .padding(.trailing, 8)
    .padding(.vertical, 4)
    .background(
      Capsule(style: .continuous)
        .fill(.textSecondary.opacity(0.12)),
    )
  }
}

// MARK: - Presentation helpers

private extension StagedFile {
  /// SF Symbol representing the file, chosen by extension.
  var symbolName: String {
    switch (name as NSString).pathExtension.lowercased() {
    case "jpg", "jpeg", "png", "heic", "gif":
      "photo"
    case "mp4", "mov":
      "film"
    case "mp3", "m4a", "wav":
      "music.note"
    case "pdf":
      "doc.richtext"
    case "zip", "rar":
      "doc.zipper"
    case "txt", "md":
      "doc.text"
    default:
      "doc"
    }
  }

  var sizeDescription: String {
    ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
  }
}

// MARK: - Preview

#if DEBUG
#Preview {
  VStack(spacing: 8) {
    ChatStagedFileTile(
      file: StagedFile(
        id: UUID(),
        name: "Quarterly-Report.pdf",
        size: 248_000,
        url: URL(fileURLWithPath: "/dev/null"),
        kind: .ownedTemp,
      )
    )      {}
    ChatStagedFileTile(
      file: StagedFile(
        id: UUID(),
        name: "archive.zip",
        size: 5_400_000,
        url: URL(fileURLWithPath: "/dev/null"),
        kind: .ownedTemp,
      )
    )      {}
  }
  .padding()
}
#endif
