//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation

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
