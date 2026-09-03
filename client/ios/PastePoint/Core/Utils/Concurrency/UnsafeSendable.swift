//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

struct UnsafeSendable<T>: @unchecked Sendable {
  nonisolated(unsafe) let value: T
}
