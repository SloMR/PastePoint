//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation

enum ChatMessageType: String, Codable, Sendable {
  case text
  case attachment
}

struct ChatMessage: Codable, Sendable, Identifiable {
  let id: UUID
  let from: String
  let text: String
  let type: ChatMessageType
  let timestamp: Date
  var fileTransfer: FileTransferData?

  private enum CodingKeys: String, CodingKey {
    case from
    case text
    case type
    case timestamp
  }

  init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.id = UUID()
    self.from = try values.decode(String.self, forKey: .from)
    self.text = try values.decode(String.self, forKey: .text)
    self.type = try values.decode(ChatMessageType.self, forKey: .type)
    self.timestamp = try values.decode(Date.self, forKey: .timestamp)
    self.fileTransfer = nil
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(from, forKey: .from)
    try container.encode(text, forKey: .text)
    try container.encode(type, forKey: .type)
    try container.encode(timestamp, forKey: .timestamp)
  }

  init(
    id: UUID = UUID(),
    from: String,
    text: String,
    type: ChatMessageType = .text,
    timestamp: Date = Date(),
    fileTransfer: FileTransferData? = nil,
  ) {
    self.id = id
    self.from = from
    self.text = text
    self.type = type
    self.timestamp = timestamp
    self.fileTransfer = fileTransfer
  }
}
