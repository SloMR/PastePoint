//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import BlakeHash
import Foundation

struct ParsedChunk: Sendable {
  let fileId: String
  let chunkIndex: UInt32
  let totalChunks: UInt32
  let data: Data
  let isValid: Bool
}

/// Binary chunk codec for file transfers byte layout exactly so iOS and web interoperate on the wire.
/// Wire frame; the layout is the protocol. Layout (all little-endian):
/// `[u16 fileId byte length][fileId UTF-8 bytes][u32 chunkIndex][u32 totalChunks][u32 CRC32][data]`
enum BinaryChunk {
  // SCTP caps messages at ~256KB; chunk data + header (~64 bytes) must stay
  // under it, so 192KB is the largest safe chunk.
  nonisolated static let chunkSize = 192 * 1024 // 192KB

  // MARK: CRC32

  private nonisolated static let crc32Table: [UInt32] = {
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
  nonisolated static func crc32(_ bytes: Data) -> UInt32 {
    var crc: UInt32 = 0xffffffff
    for byte in bytes {
      crc = crc32Table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8)
    }
    return crc ^ 0xffffffff
  }

  // MARK: Encode

  nonisolated static func encode(
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

  nonisolated static func decode(_ buffer: Data) -> ParsedChunk? {
    // Minimum: 2 (fileId len) + 0 (empty fileId) + 4 + 4 + 4 = 14 bytes.
    // TODO: Change the length of the buffer to const rather than fixed here
    guard buffer.count >= 14 else { return nil }

    // Read the header in place — `buffer` may be a slice with a non-zero
    // startIndex, so every access is rebased on `base` (Data indices are absolute).
    let base = buffer.startIndex
    var offset = 0

    func readU16() -> UInt16 {
      let i = base + offset
      let value = UInt16(buffer[i]) | (UInt16(buffer[i + 1]) << 8)
      offset += 2
      return value
    }

    func readU32() -> UInt32 {
      let i = base + offset
      let value = UInt32(buffer[i])
        | (UInt32(buffer[i + 1]) << 8)
        | (UInt32(buffer[i + 2]) << 16)
        | (UInt32(buffer[i + 3]) << 24)
      offset += 4
      return value
    }

    let fileIdLength = Int(readU16())

    // Need: fileId bytes + 12 (index + total + crc) after the length field.
    guard buffer.count >= 2 + fileIdLength + 12 else { return nil }

    let fileIdStart = base + offset
    guard
      let fileId = String(
        bytes: buffer[fileIdStart..<fileIdStart + fileIdLength],
        encoding:
        .utf8,
      )
    else { return nil }
    offset += fileIdLength

    let chunkIndex = readU32()
    let totalChunks = readU32()
    let expectedChecksum = readU32()

    let data = Data(buffer[(base + offset)...])
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
  nonisolated static func totalChunks(forFileSize fileSize: Int64) -> UInt32 {
    UInt32((fileSize + Int64(chunkSize) - 1) / Int64(chunkSize))
  }

  private nonisolated static func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
    let littleEndian = value.littleEndian
    withUnsafeBytes(of: littleEndian) { byte in
      data.append(contentsOf: byte)
    }
  }

  nonisolated static func blake3Hex(ofFileAt url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }

    var hasher = BLAKE3.Hasher()

    // TODO: Create const value for the file reading count
    while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
      hasher.update(chunk)
    }

    return hasher.finalize().map { val in
      String(format: "%02x", val)
    }.joined()
  }
}
