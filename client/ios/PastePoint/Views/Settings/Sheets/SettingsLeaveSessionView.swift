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
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(Color.red, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)

        Button {
          logger.info("Dismiss Leave Session view")
          dismiss()
        } label: {
          Text(.cancel)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.red)
            .background(Color.clear, in: Capsule())
            .overlay(
              Capsule()
                .stroke(Color.red, lineWidth: 1.5),
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
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
