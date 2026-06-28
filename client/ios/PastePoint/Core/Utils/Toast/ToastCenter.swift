//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Combine
import SwiftUI

/// App-wide toast queue. A single instance is created in `PastePointApp`,
/// injected into the SwiftUI environment, and observed by the overlay window
/// (see `ToastWindow`) so toasts float above every view — including sheets.
///
/// Call site stays simple: `toast.show(.success(.codeCopied))`.
@MainActor
final class ToastCenter: ObservableObject {
  @Published private(set) var items: [ToastItem] = []

  func show(_ item: ToastItem) {
    items.append(item)
  }

  func dismiss(_ id: ToastItem.ID) {
    items.removeAll { $0.id == id }
  }
}
