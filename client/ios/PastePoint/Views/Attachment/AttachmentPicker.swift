//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Logging
import PhotosUI
import SwiftUI

/// Shared attach flow: confirmation dialog → Files / Photos picker → stages the
/// picks via `FileStaging` and hands them back. Callers decide what to do with
/// the result (stage into chips, or send to one member).
private struct AttachmentPickerModifier: ViewModifier {
  private let logger = Logger(label: "AttachmentPicker")

  @Binding var isPresented: Bool
  let onStaged: ([StagedFile]) async -> Void

  @State private var showFileImporter = false
  @State private var showPhotoPicker = false
  @State private var photosPickerSelection: [PhotosPickerItem] = []

  func body(content: Content) -> some View {
    content
      .confirmationDialog("Attach", isPresented: $isPresented, titleVisibility: .hidden) {
        Button("Photo Library") { showPhotoPicker = true }
        Button("Files") { showFileImporter = true }
        Button("Cancel", role: .cancel) {}
      }
      .fileImporter(
        isPresented: $showFileImporter,
        allowedContentTypes: [.item],
        allowsMultipleSelection: true,
      ) { result in
        switch result {
        case .success(let urls):
          Task { await onStaged(await FileStaging.stage(urls: urls)) }
        case .failure(let error):
          // TODO: surface a toast on failure.
          logger.error("fileImporter failed: \(String(describing: error))")
        }
      }
      .photosPicker(
        isPresented: $showPhotoPicker,
        selection: $photosPickerSelection,
        maxSelectionCount: 10, // TODO: unlimited later
        matching: .any(of: [.images, .videos]),
      )
      .onChange(of: photosPickerSelection) { _, items in
        guard !items.isEmpty else { return }
        let toProcess = items
        photosPickerSelection = []
        Task { await onStaged(await FileStaging.stage(photoItems: toProcess)) }
      }
  }
}

extension View {
  /// Attaches the shared file/photo picker flow. `isPresented` triggers the
  /// "Attach" dialog; `onStaged` receives the staged files when picking finishes.
  func attachmentPicker(
    isPresented: Binding<Bool>,
    onStaged: @escaping ([StagedFile]) async -> Void,
  ) -> some View {
    modifier(AttachmentPickerModifier(isPresented: isPresented, onStaged: onStaged))
  }
}
