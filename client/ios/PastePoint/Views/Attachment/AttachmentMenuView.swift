//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Logging
import PhotosUI
import SwiftUI

/// Shared attach menu: a native `Menu` of source options (Files / Photo Library),
/// each routing through `FileStaging`. Callers supply the trigger label and an
/// `onStaged` handler (stage into chips, or send to one member).
struct AttachmentMenu<Content: View>: View {
  private let logger = Logger(label: "AttachmentMenu")

  let onStaged: ([StagedFile]) async -> Void
  @ViewBuilder let content: Content

  @State private var showFileImporter = false
  @State private var showPhotoPicker = false
  @State private var photosPickerSelection: [PhotosPickerItem] = []

  init(
    onStaged: @escaping ([StagedFile]) async -> Void,
    @ViewBuilder content: () -> Content,
  ) {
    self.onStaged = onStaged
    self.content = content()
  }

  var body: some View {
    Menu {
      Button {
        showFileImporter = true
      } label: {
        Label("Choose Files", systemImage: "folder")
      }
      // TODO: "Take Photo or Video" — camera capture (UIImagePickerController + NSCameraUsageDescription).
      Button {
        showPhotoPicker = true
      } label: {
        Label("Photo Library", systemImage: "photo.on.rectangle")
      }
    } label: {
      content
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
