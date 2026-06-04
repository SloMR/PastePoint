//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import AVFoundation
import UIKit

enum CameraPermission {
  static var status: AVAuthorizationStatus {
    AVCaptureDevice.authorizationStatus(for: .video)
  }

  static func request() async -> AVAuthorizationStatus {
    let granted = await AVCaptureDevice.requestAccess(for: .video)
    return granted ? .authorized : .denied
  }

  static func openSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
  }
}
