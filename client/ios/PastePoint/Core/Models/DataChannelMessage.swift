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

/// Wire format; do not change raw values.
enum DataChannelMessageType: String {
  case chat
  case fileOffer = "file-offer"
  case fileAccept = "file-accept"
  case fileDecline = "file-decline"
  case fileCancelUpload = "file-cancel-upload"
  case fileCancelDownload = "file-cancel-download"
  case fileReceived = "file-received"

  /// Binary frames.
  case fileChunk = "file-chunk"
}

enum DataChannelMessage {

  // MARK: Encoding

  /// Encode a DataChannelMessageType into the wire envelope: `{type:"chat", payload:{...}}`
  private static func encodeEnvelope<T: Encodable>(
    type: DataChannelMessageType,
    payload: T,
  ) throws -> Data {
    let payloadData = try JSONEncoder.dataChannel.encode(payload)
    let payloadObj = try JSONSerialization.jsonObject(with: payloadData)
    let envelope: [String: Any] = [
      "type": type.rawValue,
      "payload": payloadObj,
    ]
    return try JSONSerialization.data(withJSONObject: envelope)
  }

  static func encodeChat(_ chat: ChatMessage) throws -> Data {
    try encodeEnvelope(type: .chat, payload: chat)
  }

  static func encodeFileOffer(_ filePayload: FileOfferPayload) throws -> Data {
    try encodeEnvelope(type: .fileOffer, payload: filePayload)
  }

  static func encodeFileAccept(_ filePayload: FileAcceptPayload) throws -> Data {
    try encodeEnvelope(type: .fileAccept, payload: filePayload)
  }

  static func encodeFileDecline(_ filePayload: FileDeclinePayload) throws -> Data {
    try encodeEnvelope(type: .fileDecline, payload: filePayload)
  }

  static func encodeFileCancelUpload(_ filePayload: FileCancelPayload) throws -> Data {
    try encodeEnvelope(type: .fileCancelUpload, payload: filePayload)
  }

  static func encodeFileCancelDownload(_ filePayload: FileCancelPayload) throws -> Data {
    try encodeEnvelope(type: .fileCancelDownload, payload: filePayload)
  }

  static func encodeFileReceived(_ filePayload: FileReceivedPayload) throws -> Data {
    try encodeEnvelope(type: .fileReceived, payload: filePayload)
  }

  // MARK: Decoding

  /// Decoded inbound envelope. One case per JSON message type, plus `.unknown` for any
  /// `type` the receiver doesn't recognize (including binary-only `file-chunk`).
  enum Decoded {
    case chat(ChatMessage)
    case fileOffer(FileOfferPayload)
    case fileAccept(FileAcceptPayload)
    case fileDecline(FileDeclinePayload)
    case fileCancelUpload(FileCancelPayload)
    case fileCancelDownload(FileCancelPayload)
    case fileReceived(FileReceivedPayload)
    case unknown(type: String)
  }

  private static func decodePayload<T: Decodable>(
    _ payloadObj: Any,
    as _: T.Type,
  ) throws -> T {
    let payloadData = try JSONSerialization.data(withJSONObject: payloadObj)
    return try JSONDecoder.dataChannel.decode(T.self, from: payloadData)
  }

  static func decode(_ data: Data) throws -> Decoded {
    guard
      let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let typeRaw = obj["type"] as? String
    else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: [], debugDescription: "Bad envelope"),
      )
    }

    guard let payloadObj = obj["payload"] else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: [], debugDescription: "Missing payload"),
      )
    }

    switch DataChannelMessageType(rawValue: typeRaw) {
    case .chat:
      return .chat(try decodePayload(payloadObj, as: ChatMessage.self))
    case .fileOffer:
      return .fileOffer(try decodePayload(payloadObj, as: FileOfferPayload.self))
    case .fileAccept:
      return .fileAccept(try decodePayload(payloadObj, as: FileAcceptPayload.self))
    case .fileDecline:
      return .fileDecline(try decodePayload(payloadObj, as: FileDeclinePayload.self))
    case .fileCancelUpload:
      return .fileCancelUpload(try decodePayload(payloadObj, as: FileCancelPayload.self))
    case .fileCancelDownload:
      return .fileCancelDownload(try decodePayload(payloadObj, as: FileCancelPayload.self))
    case .fileReceived:
      return .fileReceived(try decodePayload(payloadObj, as: FileReceivedPayload.self))
    case .fileChunk, nil:
      return .unknown(type: typeRaw)
    }
  }
}
