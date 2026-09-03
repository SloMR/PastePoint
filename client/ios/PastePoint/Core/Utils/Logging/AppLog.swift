//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation
import Logging
import os

nonisolated let log = AppLog()

struct AppLog: Sendable {
  private let cache = OSAllocatedUnfairLock<[String: Logging.Logger]>(initialState: [:])

  nonisolated init() {}

  private nonisolated func logger(for file: String) -> Logging.Logger {
    cache.withLock { store in
      if let existing = store[file] { return existing }
      let created = Logging.Logger(label: Self.category(from: file))
      store[file] = created
      return created
    }
  }

  private nonisolated static func category(from fileID: String) -> String {
    let name = fileID.split(separator: "/").last.map(String.init) ?? fileID
    return name.hasSuffix(".swift") ? String(name.dropLast(6)) : name
  }

  nonisolated func debug(_ msg: @autoclosure () -> String, file: String = #fileID, function: String = #function, line: UInt = #line) {
    logger(for: file).debug("\(msg())", file: file, function: function, line: line)
  }

  nonisolated func info(_ msg: @autoclosure () -> String, file: String = #fileID, function: String = #function, line: UInt = #line) {
    logger(for: file).info("\(msg())", file: file, function: function, line: line)
  }

  nonisolated func notice(_ msg: @autoclosure () -> String, file: String = #fileID, function: String = #function, line: UInt = #line) {
    logger(for: file).notice("\(msg())", file: file, function: function, line: line)
  }

  nonisolated func warning(_ msg: @autoclosure () -> String, file: String = #fileID, function: String = #function, line: UInt = #line) {
    logger(for: file).warning("\(msg())", file: file, function: function, line: line)
  }

  nonisolated func error(_ msg: @autoclosure () -> String, file: String = #fileID, function: String = #function, line: UInt = #line) {
    logger(for: file).error("\(msg())", file: file, function: function, line: line)
  }

  nonisolated func critical(_ msg: @autoclosure () -> String, file: String = #fileID, function: String = #function, line: UInt = #line) {
    logger(for: file).critical("\(msg())", file: file, function: function, line: line)
  }
}

extension Error {
  /// Domain and code only; localized descriptions can embed file names.
  nonisolated var codeDescription: String {
    let error = self as NSError
    return "\(error.domain)#\(error.code)"
  }
}
