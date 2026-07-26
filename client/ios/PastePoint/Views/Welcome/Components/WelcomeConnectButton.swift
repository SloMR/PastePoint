//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct WelcomeConnectButton: View {
  let label: LocalizedStringResource
  let prominent: Bool
  let isBusy: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        if isBusy {
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
        Text(isBusy ? .starting : label)
      }
    }
    .buttonStyle(.pill(prominent ? .filled : .outlined, tint: AppColors.Brand.brand))
    .disabled(isBusy)
    .padding(.top, 2)
  }
}

// MARK: - Preview

#if DEBUG
#Preview {
  PreviewStage {
    VStack(spacing: 12) {
      WelcomeConnectButton(label: .connectADevice, prominent: true, isBusy: false) {}
      WelcomeConnectButton(label: .connectADevice, prominent: false, isBusy: false) {}
      WelcomeConnectButton(label: .connectADevice, prominent: true, isBusy: true) {}
    }
    .padding()
  }
}
#endif
