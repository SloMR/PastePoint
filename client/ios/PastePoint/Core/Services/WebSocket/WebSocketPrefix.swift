//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

/// Server prefixes on WebSocket text frames
enum WebSocketPrefix: String {
  case systemMessage = "[SystemMessage]"
  case systemRooms = "[SystemRooms]"
  case systemName = "[SystemName]"
  case systemJoin = "[SystemJoin]"
  case systemMembers = "[SystemMembers]"
  case signalMessage = "[SignalMessage]"
  case userCommand = "[UserCommand]"
}
