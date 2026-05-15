//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation

enum SignalPayload {
  case offer(sdp: String)
  case answer(sdp: String)
  case candidate(sdp: String, sdpMid: String?, sdpMLineIndex: Int32)
  case connectionRequest

  var typeString: String {
    switch self {
    case .offer: return "offer"
    case .answer: return "answer"
    case .candidate: return "candidate"
    case .connectionRequest: return "connection_request"
    }
  }

  var dataDict: [String: Any] {
    switch self {
    case .offer(let sdp):
      return ["type": "offer", "sdp": sdp]
    case .answer(let sdp):
      return ["type": "answer", "sdp": sdp]
    case .candidate(let sdp, let sdpMid, let sdpMLineIndex):
      var dict: [String: Any] = [
        "candidate": sdp,
        "sdpMLineIndex": Int(sdpMLineIndex),
      ]

      if let sdpMid { dict["sdpMid"] = sdpMid }
      return dict
    case .connectionRequest:
      return [:]
    }
  }

  init?(typeString: String, data: Any?) {
    switch typeString {
    case "offer":
      guard let dict = data as? [String: Any], let sdp = dict["sdp"] as? String else { return nil }
      self = .offer(sdp: sdp)
    case "answer":
      guard let dict = data as? [String: Any], let sdp = dict["sdp"] as? String else { return nil }
      self = .answer(sdp: sdp)
    case "candidate":
      guard let dict = data as? [String: Any], let sdp = dict["candidate"] as? String else { return nil }

      let rawSdpMid = dict["sdpMid"] as? String
      let sdpMid = (rawSdpMid?.isEmpty == false) ? rawSdpMid : nil
      let sdpMLineIndex = Int32((dict["sdpMLineIndex"] as? Int) ?? 0)
      self = .candidate(sdp: sdp, sdpMid: sdpMid, sdpMLineIndex: sdpMLineIndex)
    case "connection_request":
      self = .connectionRequest
    default:
      return nil
    }
  }
}

struct SignalMessage {
  let payload: SignalPayload
  let from: String
  let to: String
  let sequence: Int?

  init?(from dict: [String: Any]) {
    guard
      let typeRaw = dict["type"] as? String,
      let fromRaw = dict["from"] as? String,
      let toRaw = dict["to"] as? String,
      let payload = SignalPayload(typeString: typeRaw, data: dict["data"])
    else { return nil }

    self.payload = payload
    self.from = fromRaw
    self.to = toRaw
    self.sequence = dict["sequence"] as? Int
  }

  init(payload: SignalPayload, from: String, to: String, sequence: Int? = nil) {
    self.payload = payload
    self.from = from
    self.to = to
    self.sequence = sequence
  }

  func toDict() -> [String: Any] {
    var dict: [String: Any] = [
      "type": payload.typeString,
      "data": payload.dataDict,
      "from": from,
      "to": to,
    ]

    if let sequence { dict["sequence"] = sequence }
    return dict
  }
}
