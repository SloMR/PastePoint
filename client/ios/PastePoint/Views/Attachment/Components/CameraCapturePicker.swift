//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum CameraCapture {
  case photo(Data)
  case video(URL)
}

struct CameraCapturePicker: UIViewControllerRepresentable {
  let onCapture: (CameraCapture?) -> Void

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let picker = UIImagePickerController()
    picker.sourceType = .camera
    picker.mediaTypes = UIImagePickerController.availableMediaTypes(for: .camera) ?? [UTType.image.identifier]
    picker.videoQuality = .typeHigh
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(onCapture: onCapture)
  }

  final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let onCapture: (CameraCapture?) -> Void

    init(onCapture: @escaping (CameraCapture?) -> Void) {
      self.onCapture = onCapture
    }

    func imagePickerController(
      _ picker: UIImagePickerController,
      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any],
    ) {
      if let url = info[.mediaURL] as? URL {
        onCapture(.video(url))
      } else if
        let image = info[.originalImage] as? UIImage,
        let data = image.jpegData(compressionQuality: 0.9)
      {
        onCapture(.photo(data))
      } else {
        onCapture(nil)
      }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
      onCapture(nil)
    }
  }
}
