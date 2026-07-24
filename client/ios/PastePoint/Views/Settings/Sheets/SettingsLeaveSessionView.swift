//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct SettingsLeaveSessionView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var services: AppServices

  var onSessionLeft: (() -> Void)?

  @State private var isLeaving = false

  var body: some View {
    VStack(spacing: 20) {
      Text(.endSessionHeader)
        .font(.headline)
        .multilineTextAlignment(.center)
        .foregroundStyle(.primary)
        .padding(.horizontal)

      HStack(spacing: 12) {
        Button {
          Task { await leaveSession() }
        } label: {
          HStack(spacing: 8) {
            if isLeaving {
              ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .scaleEffect(0.85)
            }
            Text(isLeaving ? .leaving : .endTheSession)
          }
        }
        .buttonStyle(.pill(tint: .red))
        .disabled(isLeaving)

        Button {
          log.info("Dismiss Leave Session view")
          dismiss()
        } label: {
          Text(.cancel)
        }
        .buttonStyle(.pill(.outlined, tint: .red))
        .disabled(isLeaving)
      }
    }
    .padding(24)
    .sheetContainer(title: .endSession)
  }

  private func leaveSession() async {
    log.info("User confirmed leaving private session")
    isLeaving = true
    services.wsService.disconnect(manual: true)
    if await services.connectIfPermitted(sessionCode: nil) {
      await services.roomService.listRooms()
      await services.userService.getUsername()
    }
    isLeaving = false
    log.info("Left private session")
    dismiss()
    onSessionLeft?()
  }
}

// MARK: - Preview

#if DEBUG
#Preview {
  SettingsLeaveSessionView()
    .environmentObject(AppServices.preview)
}
#endif
