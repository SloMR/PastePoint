//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SafariServices
import SwiftUI

// MARK: - Identifiable URL

struct IdentifiableURL: Identifiable {
  let id = UUID()
  let url: URL
}

// MARK: - Safari View

struct SafariView: UIViewControllerRepresentable {
  let url: URL

  func makeUIViewController(context: Context) -> SFSafariViewController {
    let config = SFSafariViewController.Configuration()
    config.entersReaderIfAvailable = false
    let vc = SFSafariViewController(url: url, configuration: config)
    vc.preferredControlTintColor = .brand
    return vc
  }

  func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
