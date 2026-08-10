//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Combine
import SwiftUI

/// App-wide toast queue. One instance lives in `PastePointApp` and the overlay window
/// observes it, so a call site only ever writes `toast.show(.success(.codeCopied))`.
@MainActor
final class ToastCenter: ObservableObject {
  static let displayDuration: Double = 2

  /// One docked slot plus two queued capsules, so a burst can't bury the chat.
  private static let maxVisible = 3

  @Published private(set) var items: [ToastItem] = []

  /// Looked up on every `show`, since at init there is no window to measure yet.
  @Published private(set) var cutout: ToastCutout?

  /// True while a toast is covering the clock and status icons.
  var isDocked: Bool {
    cutout != nil && !items.isEmpty
  }

  func show(_ item: ToastItem) {
    var item = item
    item.id = UUID()

    cutout = ToastCutout.current()
    items.append(item)
    if items.count > Self.maxVisible {
      // Drop a queued one, never index 0 — that toast is on screen and may be mid-animation.
      items.remove(at: 1)
    }

    // VoiceOver never reaches the overlay's own window, so announce the toast ourselves.
    AccessibilityNotification.Announcement(String(localized: item.message)).post()
  }

  func dismiss(_ id: ToastItem.ID) {
    items.removeAll { $0.id == id }
  }
}
