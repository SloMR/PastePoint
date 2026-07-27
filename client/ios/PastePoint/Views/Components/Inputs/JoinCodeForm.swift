//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct JoinCodeForm: View {
  @EnvironmentObject private var services: AppServices
  @EnvironmentObject private var toast: ToastCenter

  var onSessionJoin: (() -> Void)?

  @State private var sessionCode: String = ""
  @State private var isScannerPresented: Bool = false
  @State private var isJoining: Bool = false

  private var trimmedCode: String {
    sessionCode.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
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
            Text(isJoining ? .joining : .join)
          }
        }
        .buttonStyle(.pill(tint: AppColors.Brand.brand))
        .disabled(trimmedCode.isEmpty || isJoining)
        .opacity(trimmedCode.isEmpty ? 0.6 : 1)

      }
    }
    .fullScreenCover(isPresented: $isScannerPresented) {
      ScanQRCodeView { scannedCode in
        sessionCode = scannedCode
        Task { await joinSession(code: scannedCode) }
      }
    }
  }

  private func joinSession(code: String) async {
    let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    guard let resolved = SessionService.sessionCode(fromPayload: trimmed) else {
      log.warning("Invalid session code entered")
      toast.show(.error(.invalidSessionCode))
      return
    }

    log.info("Joining private session with code: \(resolved)")
    isJoining = true
    defer { isJoining = false }

    await services.wsService.setupPrivateSession(resolved)
    guard await services.connectIfPermitted() else {
      toast.show(.error(.localNetworkOffJoin))
      return
    }

    sessionCode = ""
    onSessionJoin?()
  }
}

// MARK: - Preview

#if DEBUG
#Preview {
  JoinCodeForm()
    .padding()
    .environmentObject(AppServices.preview)
    .environmentObject(ToastCenter())
}
#endif
