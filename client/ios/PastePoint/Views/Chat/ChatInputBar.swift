//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Logging
import PhotosUI
import SwiftUI

struct ChatInputBar: View {
  private let logger = Logger(label: "ChatInputBar")
  let onSend: (String) -> Bool
  let onSendFiles: ([StagedFile]) -> Bool

  @State private var message = ""
  @State private var stagedFiles: [StagedFile] = []
  @State private var showAttachDialog: Bool = false
  @State private var showFileImporter: Bool = false
  @State private var showPhotoPicker: Bool = false
  @State private var photosPickerSelection: [PhotosPickerItem] = []

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
        Button {
          logger.info("Attachments Button Clicked")
          showAttachDialog = true
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
    .confirmationDialog("Attach", isPresented: $showAttachDialog, titleVisibility: .hidden) {
      Button("Photo Library") {
        showPhotoPicker = true
      }
      Button("Files") {
        showFileImporter = true
      }
      Button("Cancel", role: .cancel) { }
    }
    .fileImporter(
      isPresented: $showFileImporter,
      allowedContentTypes: [.item],
      allowsMultipleSelection: true,
    ) { result in
      switch result {
      case .success(let urls):
        Task { await stageFromFilePicker(urls: urls) }
      case .failure(let error):
        // TODO: Add toast if needed and haptic also
        logger.error("fileImporter failed: \(String(describing: error))")
      }
    }
    .photosPicker(
      isPresented: $showPhotoPicker,
      selection: $photosPickerSelection,
      maxSelectionCount: 10, // TODO: Change this to unlimited later
      matching: .any(of: [.images, .videos]),
    )
    .onChange(of: photosPickerSelection) { _, items in
      guard !items.isEmpty else { return }

      let toProcess = items
      photosPickerSelection = []
      Task { await stageFromPhotosPicker(items: toProcess) }
    }
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

  private func stageFromFilePicker(urls: [URL]) async {
    for url in urls {
      let didStart = url.startAccessingSecurityScopedResource()

      defer {
        if didStart {
          url.stopAccessingSecurityScopedResource()
        }
      }

      let fileName = url.lastPathComponent
      let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(fileName)")

      do {
        try FileManager.default.copyItem(at: url, to: tmpURL)
        let attribute = try FileManager.default.attributesOfItem(atPath: tmpURL.path)
        let size = (attribute[.size] as? NSNumber)?.int64Value ?? 0

        stagedFiles.append(StagedFile(id: UUID(), name: fileName, size: size, url: tmpURL))
        logger.info("staged file: \(fileName) (\(size) bytes)")
      } catch {
        logger.error("failed to stage \(fileName): \(String(describing: error))")
      }
    }
  }

  private func stageFromPhotosPicker(items: [PhotosPickerItem]) async {
    for item in items {
      do {
        guard let data = try await item.loadTransferable(type: Data.self) else {
          logger.error("photosPicker item returned nil data")
          continue
        }

        let fileExtension = item.supportedContentTypes.first?.preferredFilenameExtension ?? "bin"
        let fileName = "\(UUID().uuidString).\(fileExtension)"
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        try data.write(to: tmpURL)
        stagedFiles.append(StagedFile(id: UUID(), name: fileName, size: Int64(data.count), url: tmpURL))
        logger.info("staged photo: \(fileName) (\(data.count) bytes)")
      } catch {
        logger.error("failed to stage photo: \(String(describing: error))")
      }
    }
  }
}

// MARK: - Preview

#if DEBUG
#Preview {
  ChatInputBar(onSend: { _ in true }, onSendFiles: { _ in true })
}
#endif
