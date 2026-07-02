//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Logging
import SwiftUI

struct SettingsLeaveSessionView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var services: AppServices

  private let logger = Logger(label: "SettingsLeaveSessionView")

  var onSessionLeft: (() -> Void)?

  var body: some View {
    VStack(spacing: 20) {
      Text(.endSessionHeader)
        .font(.headline)
        .multilineTextAlignment(.center)
        .foregroundStyle(.primary)
        .padding(.horizontal)

      HStack(spacing: 12) {
        Button {
          logger.info("User confirmed leaving private session")
          services.wsService.disconnect(manual: true)
          Task {
            if await services.connectIfPermitted(sessionCode: nil) {
              await services.roomService.listRooms()
              await services.userService.getUsername()
            }
            logger.info("Left private session")
            dismiss()
            onSessionLeft?()
          }
        } label: {
          Text(.endTheSession)
        }
        .buttonStyle(.pill(tint: .red))

        Button {
          logger.info("Dismiss Leave Session view")
          dismiss()
        } label: {
          Text(.cancel)
        }
        .buttonStyle(.pill(.outlined, tint: .red))
      }
    }
    .padding(24)
    .sheetContainer(title: .endSession)
  }
}

// MARK: - Preview

#if DEBUG
#Preview {
  SettingsLeaveSessionView()
    .environmentObject(AppServices.preview)
}
#endif
