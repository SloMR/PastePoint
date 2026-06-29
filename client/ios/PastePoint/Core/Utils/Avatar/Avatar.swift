//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation

enum ChatAvatar {
  /// Number of peer avatars bundled as `bottts-00` … `bottts-(count-1)`.
  static let count: UInt32 = 24
  static let selfImageName = "bottts-self"

  /// Deterministic, locale-independent string hash (djb2).
  private static func hash(_ seed: String) -> UInt32 {
    var hash: UInt32 = 5381
    for byte in seed.unicodeScalars {
      hash = (hash &<< 5) &+ hash &+ (byte.value & 0xFF)
    }
    return hash
  }

  static func imageName(for name: String, isMine: Bool) -> String {
    guard !isMine else { return selfImageName }
    return String(format: "bottts-%02d", hash(name) % count)
  }
}
