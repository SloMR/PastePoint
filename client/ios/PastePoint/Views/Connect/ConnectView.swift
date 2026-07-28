//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct ConnectView: View {
  @EnvironmentObject private var services: AppServices
  @EnvironmentObject private var toast: ToastCenter

  var onSessionJoin: (() -> Void)?

  private var sessionCode: String? {
    services.wsService.currentSessionCode
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if let code = sessionCode {
        shareSection(code: code)
      } else {
        createSection
      }

      Divider()

      VStack(alignment: .leading, spacing: 10) {
        Text(.joiningSomeoneElse)
          .font(.caption)
          .fontWeight(.semibold)
          .foregroundStyle(.textSecondary)

        JoinCodeForm(onSessionJoin: onSessionJoin)
      }
    }
    .padding(24)
    .sheetContainer(title: .connectDeviceTitle)
  }

  // MARK: - Share

  private func shareSection(code: String) -> some View {
    SessionShareBlock(code: code)
  }

  // MARK: - Create

  private var createSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(
        services.peerDirectory.peers.isEmpty
          ? .optionElsewhereBody
          : .optionElsewhereBodyConnected,
      )
      .font(.caption)
      .foregroundStyle(.textSecondary)
      .fixedSize(horizontal: false, vertical: true)

      WelcomeInviteButton()
    }
  }

}

// MARK: - Preview

#if DEBUG
#Preview {
  ConnectView()
    .environmentObject(AppServices.preview)
    .environmentObject(ToastCenter())
}
#endif
