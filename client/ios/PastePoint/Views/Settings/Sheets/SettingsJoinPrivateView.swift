//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Logging
import SwiftUI

struct SettingsJoinPrivateView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var services: AppServices

  private let logger = Logger(label: "SettingsJoinPrivateView")

  var onSessionJoin: (() -> Void)?

  @State private var sessionCode: String = ""
  @State private var sheetHeight: CGFloat = 320
  @State private var isScannerPresented: Bool = false
  @State private var isJoining: Bool = false
  @State private var toasts: [ToastItem] = []

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 16) {

        // Input
        VStack(alignment: .leading, spacing: 6) {
          Text("Enter the Session Code")
            .font(.subheadline)
            .foregroundStyle(.textPrimary)

          HStack(spacing: 0) {
            TextField("Session code", text: $sessionCode)
              .textFieldStyle(.plain)
              .font(.body)
              .foregroundStyle(.textPrimary)
              .autocorrectionDisabled()
              .textInputAutocapitalization(.never)
              .padding(.leading, 14)
              .padding(.vertical, 12)

            if !sessionCode.isEmpty {
              Button { sessionCode = "" } label: {
                Image(systemName: "xmark.circle.fill")
                  .font(.system(size: 16))
                  .foregroundStyle(.textSecondary)
                  .frame(width: 36, height: 44)
              }
              .buttonStyle(.plain)
            }

            Button {
              isScannerPresented = true
            } label: {
              Image(systemName: "camera.viewfinder")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(AppColors.Brand.brand)
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)
          }
          .background(AppColors.Background.input, in: RoundedRectangle(cornerRadius: 8))

          Text("Enter the code to join a private chat.")
            .font(.caption)
            .foregroundStyle(.textSecondary)
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
              Text(isJoining ? "Joining…" : "Done")
                .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(AppColors.Brand.brand, in: Capsule())
          }
          .buttonStyle(.plain)
          .disabled(sessionCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isJoining)
          .opacity(sessionCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1)

          Button {
            logger.info("Dismiss join private session")
            dismiss()
          } label: {
            Text("Cancel")
              .fontWeight(.semibold)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 14)
              .foregroundStyle(AppColors.Brand.brand)
              .background(Color.clear, in: Capsule())
              .overlay(Capsule().stroke(AppColors.Brand.brand, lineWidth: 1.5))
          }
          .buttonStyle(.plain)
          .disabled(isJoining)
        }
      }
      .padding(24)
      .frame(maxWidth: .infinity)
      .fixedSize(horizontal: false, vertical: true)
      .onGeometryChange(for: CGFloat.self) { proxy in
        proxy.size.height
      } action: { height in
        guard height > 0 else { return }
        sheetHeight = height + 56
      }
      .navigationTitle("Join a Private Session")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          if #available(iOS 26, *) {
            Button(role: .close) {
              dismiss()
            }
          } else {
            Button { dismiss() } label: {
              ZStack {
                Circle()
                  .fill(Color(UIColor.tertiarySystemFill))
                  .frame(width: 36, height: 36)

                Image(systemName: "xmark")
                  .font(.system(size: 13, weight: .bold, design: .rounded))
                  .foregroundStyle(Color(UIColor.secondaryLabel))
              }
              .contentShape(Circle())
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
    .presentationDetents([.height(sheetHeight)])
    .presentationDragIndicator(.visible)
    .presentationBackground(AppColors.Background.background)
    .appToast(items: $toasts)
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
      toasts.append(.error("Invalid session code"))
      return
    }
    logger.info("Joining private session with code: \(trimmed)")
    isJoining = true
    await services.wsService.setupPrivateSession(trimmed)
    guard await services.connectIfPermitted() else {
      isJoining = false
      toasts.append(.error("Local network is off — enable it in Settings to join"))
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
}
#endif
