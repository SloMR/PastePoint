//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import MessageUI
import SwiftUI

struct ReportComposerView: UIViewControllerRepresentable {
  let message: ChatMessage
  let isPrivateRoom: Bool
  let onFinish: () -> Void

  private static let maxReportedText = 1000

  static var canSendMail: Bool { MFMailComposeViewController.canSendMail() }

  func makeUIViewController(context: Context) -> MFMailComposeViewController {
    let composer = MFMailComposeViewController()
    composer.mailComposeDelegate = context.coordinator
    composer.setToRecipients([AppEnvironment.supportEmail])
    composer.setSubject(String(localized: .reportEmailSubject))
    composer.setMessageBody(body, isHTML: false)
    return composer
  }

  func updateUIViewController(_: MFMailComposeViewController, context _: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(onFinish: onFinish)
  }

  private var body: String {
    var lines = [
      String(localized: .reportEmailIntro),
      "",
      "",
      "",
      "---",
      "App: \(Bundle.main.appVersion) (\(Bundle.main.appBuild))",
      "Device: \(UIDevice.current.model), \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
      "Room: \(isPrivateRoom ? "Private session" : "Public room")",
      "",
    ]

    if let transfer = message.fileTransfer {
      let size = ByteCountFormatter.string(fromByteCount: transfer.fileSize, countStyle: .file)
      lines.append("Reported file: \(transfer.fileName) (\(size))")
    } else {
      lines.append("Reported message:")
      lines.append(Self.truncated(message.text))
    }

    return lines.joined(separator: "\n")
  }

  private static func truncated(_ text: String) -> String {
    text.count <= maxReportedText ? text : "\(text.prefix(maxReportedText))…"
  }

  final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
      self.onFinish = onFinish
    }

    func mailComposeController(
      _: MFMailComposeViewController,
      didFinishWith _: MFMailComposeResult,
      error _: Error?,
    ) {
      onFinish()
    }
  }
}
