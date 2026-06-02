//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation

struct ParsedChunk: Sendable {
  let fileId: String
  let chunkIndex: UInt32
  let totalChunks: UInt32
  let data: Data
  let isValid: Bool
}

/// Binary chunk codec for file transfers byte layout exactly so iOS and web interoperate on the wire.
/// Layout (all little-endian):
/// `[u16 fileId byte length][fileId UTF-8 bytes][u32 chunkIndex][u32 totalChunks][u32 CRC32][data]`
enum BinaryChunk {
  static let chunkSize = 64 * 1024 // 64KB

  // MARK: CRC32

  private static let crc32Table: [UInt32] = {
    var table = [UInt32](repeating: 0, count: 256)
    for i in 0..<256 {
      var crc = UInt32(i)
      for _ in 0..<8 {
        crc = (crc & 1 == 1) ? (crc >> 1) ^ 0xedb88320 : crc >> 1
      }
      table[i] = crc
    }
    return table
  }()

  /// Standard CRC32 — polynomial 0xedb88320, init 0xffffffff, final XOR 0xffffffff.
  static func crc32(_ bytes: Data) -> UInt32 {
    var crc: UInt32 = 0xffffffff
    for byte in bytes {
      crc = crc32Table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8)
    }
    return crc ^ 0xffffffff
  }

  // MARK: Encode

  static func encode(
    fileId: String,
    chunkIndex: UInt32,
    totalChunks: UInt32,
    data: Data,
  ) -> Data {
    let fileIdBytes = Data(fileId.utf8)
    let fileIdLength = UInt16(fileIdBytes.count)
    let checksum = crc32(data)

    var buffer = Data(capacity: 2 + fileIdBytes.count + 12 + data.count)
    appendLittleEndian(fileIdLength, to: &buffer)
    buffer.append(fileIdBytes)
    appendLittleEndian(chunkIndex, to: &buffer)
    appendLittleEndian(totalChunks, to: &buffer)
    appendLittleEndian(checksum, to: &buffer)
    buffer.append(data)
    return buffer
  }

  static func decode(_ buffer: Data) -> ParsedChunk? {
    // Minimum: 2 (fileId len) + 0 (empty fileId) + 4 + 4 + 4 = 14 bytes.
    // TODO: Change the length of the buffer to const rather than fixed here
    guard buffer.count >= 14 else { return nil }

    // Re-base to a contiguous zero-based view — a sliced Data can have a
    // non-zero startIndex, which would break manual offset math.
    let bytes = [UInt8](buffer)
    var offset = 0

    func readU16() -> UInt16 {
      let value = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
      offset += 2
      return value
    }

    func readU32() -> UInt32 {
      let value = UInt32(bytes[offset])
        | (UInt32(bytes[offset + 1]) << 8)
        | (UInt32(bytes[offset + 2]) << 16)
        | (UInt32(bytes[offset + 3]) << 24)

      offset += 4
      return value
    }

    let fileIdLength = Int(readU16())

    // Need: fileId bytes + 12 (index + total + crc) after the length field.
    guard bytes.count >= 2 + fileIdLength + 12 else { return nil }

    let fileIdBytes = bytes[offset..<offset + fileIdLength]
    offset += fileIdLength
    guard let fileId = String(bytes: fileIdBytes, encoding: .utf8) else { return nil }

    let chunkIndex = readU32()
    let totalChunks = readU32()
    let expectedChecksum = readU32()

    let data = Data(bytes[offset...])
    let isValid = crc32(data) == expectedChecksum

    return ParsedChunk(
      fileId: fileId,
      chunkIndex: chunkIndex,
      totalChunks: totalChunks,
      data: data,
      isValid: isValid,
    )
  }

  // MARK: Helpers

  /// Ceiling division — how many chunks a file of `fileSize` bytes needs.
  static func totalChunks(forFileSize fileSize: Int64) -> UInt32 {
    UInt32((fileSize + Int64(chunkSize) - 1) / Int64(chunkSize))
  }

  private static func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
    let littleEndian = value.littleEndian
    withUnsafeBytes(of: littleEndian) { byte in
      data.append(contentsOf: byte)
    }
  }
}
