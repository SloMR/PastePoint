//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation

private extension JSONEncoder {
  static let dataChannel: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()
}

private extension JSONDecoder {
  static let dataChannel: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()
}

enum DataChannelMessageType: String {
  case chat
  case file
}

enum DataChannelMessage {

  /// Encode a chat message into the wire envelope: `{type:"chat", payload:{...}}`
  static func encodeChat(_ chat: ChatMessage) throws -> Data {
    let payloadData = try JSONEncoder.dataChannel.encode(chat)
    let payload = try JSONSerialization.jsonObject(with: payloadData)
    let envelope: [String: Any] = [
      "type": DataChannelMessageType.chat.rawValue,
      "payload": payload,
    ]
    return try JSONSerialization.data(withJSONObject: envelope)
  }

  /// Decode an inbound envelope. Returns `.chat(ChatMessage)` or `.unknown(type)`.
  enum Decoded {
    case chat(ChatMessage)
    case unknown(type: String)
  }

  static func decode(_ data: Data) throws -> Decoded {
    guard
      let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let typeRaw = obj["type"] as? String
    else {
      throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Bad envelope"))
    }

    switch DataChannelMessageType(rawValue: typeRaw) {
    case .chat:
      guard let payload = obj["payload"] as? [String: Any] else {
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Bad chat payload"))
      }
      let payloadData = try JSONSerialization.data(withJSONObject: payload)
      let chat = try JSONDecoder.dataChannel.decode(ChatMessage.self, from: payloadData)
      return .chat(chat)
    case .file, nil:
      return .unknown(type: typeRaw)
    }
  }
}
