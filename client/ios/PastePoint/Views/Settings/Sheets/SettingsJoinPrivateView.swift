//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Logging
import SwiftUI

struct SettingsJoinPrivateView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var services: AppServices
  @EnvironmentObject private var toast: ToastCenter

  private let logger = Logger(label: "SettingsJoinPrivateView")

  var onSessionJoin: (() -> Void)?

  @State private var sessionCode: String = ""
  @State private var isScannerPresented: Bool = false
  @State private var isJoining: Bool = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {

      LabeledInputField(
        label: .enterSessionCode,
        placeholder: .sessionCodePlaceholder,
        text: $sessionCode,
        description: .sessionCodeDescription,
      ) {
        Button {
          isScannerPresented = true
        } label: {
          Image(systemName: "camera.viewfinder")
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(AppColors.Brand.brand)
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.scanQrCode))
        .padding(.trailing, 4)
      }

      // Buttons
      HStack(spacing: 12) {
        Button {
          Task { await joinSession(code: sessionCode) }
        } label: {
          HStack(spacing: 8) {
            if isJoining {
              ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .scaleEffect(0.85)
            }
            Text(isJoining ? .joining : .done)
          }
        }
        .buttonStyle(.pill(tint: AppColors.Brand.brand))
        .disabled(sessionCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isJoining)
        .opacity(sessionCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1)

        Button {
          logger.info("Dismiss join private session")
          dismiss()
        } label: {
          Text(.cancel)
        }
        .buttonStyle(.pill(.outlined, tint: AppColors.Brand.brand))
        .disabled(isJoining)
      }
    }
    .padding(24)
    .sheetContainer(title: .joinAPrivateSession)
    .fullScreenCover(isPresented: $isScannerPresented) {
      SettingsScanQRCodeView { scannedCode in
        sessionCode = scannedCode
        Task { await joinSession(code: scannedCode) }
      }
    }
  }

  private func joinSession(code: String) async {
    let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    guard SessionService.isValidSessionCode(trimmed) else {
      logger.warning("Invalid session code entered: \(trimmed)")
      toast.show(.error(.invalidSessionCode))
      return
    }
    logger.info("Joining private session with code: \(trimmed)")
    isJoining = true
    await services.wsService.setupPrivateSession(trimmed)
    guard await services.connectIfPermitted() else {
      isJoining = false
      toast.show(.error(.localNetworkOffJoin))
      return
    }
    isJoining = false
    dismiss()
    onSessionJoin?()
    Task {
      await services.roomService.listRooms()
      await services.userService.getUsername()
    }
  }
}

// MARK: - Preview

#if DEBUG
#Preview {
  SettingsJoinPrivateView()
    .environmentObject(AppServices.preview)
    .environmentObject(ToastCenter())
}
#endif
