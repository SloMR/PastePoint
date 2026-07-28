//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct WelcomeInviteButton: View {
  @EnvironmentObject private var services: AppServices
  @EnvironmentObject private var toast: ToastCenter

  var prominent: Bool = true

  @State private var isStarting = false

  var body: some View {
    Button {
      Task { await createInviteLink() }
    } label: {
      HStack(spacing: 8) {
        if isStarting {
          ProgressView()
            .progressViewStyle(.circular)
            .tint(prominent ? .white : AppColors.Brand.brand)
            .scaleEffect(0.85)
        } else {
          Image("qrcode")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
        }
        Text(isStarting ? .starting : .connectADevice)
      }
    }
    .buttonStyle(.pill(prominent ? .filled : .outlined, tint: AppColors.Brand.brand))
    .disabled(isStarting)
    .padding(.top, 2)
  }

  private func createInviteLink() async {
    isStarting = true
    defer { isStarting = false }
    do {
      log.info("Create an invite link tapped")
      try await services.sessionService.preparePrivateSession()
      guard await services.connectIfPermitted() else {
        toast.show(.error(.localNetworkOffStart))
        return
      }
      toast.show(.success(.privateSessionStarted))
    } catch {
      log.error("Cannot get the session code \(error)")
      toast.show(.error(.startPrivateFailed))
    }
  }
}

// MARK: - Preview

#if DEBUG
#Preview {
  PreviewStage {
    VStack(spacing: 12) {
      WelcomeInviteButton()
      WelcomeInviteButton(prominent: false)
    }
    .padding()
    .environmentObject(AppServices.preview)
    .environmentObject(ToastCenter())
  }
}
#endif
