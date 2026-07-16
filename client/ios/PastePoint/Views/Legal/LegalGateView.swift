//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct LegalGateView: View {
  @State private var safariURL: IdentifiableURL?

  let onAccept: () -> Void

  var body: some View {
    VStack(spacing: 20) {
      ZStack {
        Circle()
          .fill(AppColors.Brand.accent.opacity(0.12))
          .frame(width: 104, height: 104)

        Image(systemName: "hand.raised.fill")
          .resizable()
          .scaledToFit()
          .frame(width: 48, height: 48)
          .foregroundStyle(AppColors.Brand.accent)
      }

      VStack(spacing: 10) {
        Text(.legalGateTitle)
          .font(.title2.bold())
          .foregroundStyle(.textPrimary)
          .multilineTextAlignment(.center)

        Text(.legalGateMessage)
          .font(.body)
          .foregroundStyle(.textSecondary)
          .multilineTextAlignment(.center)

        Text(.legalGateZeroTolerance)
          .font(.subheadline)
          .foregroundStyle(.textSecondary)
          .multilineTextAlignment(.center)
          .padding(.top, 4)
      }
      .padding(.horizontal)

      VStack(spacing: 12) {
        Button {
          onAccept()
        } label: {
          Text(.legalGateAccept)
        }
        .buttonStyle(.pill(tint: AppColors.Brand.accent))

        Button {
          if let url = URL(string: AppEnvironment.legalUrl) {
            safariURL = IdentifiableURL(url: url)
          }
        } label: {
          Text(.privacyAndTerms)
            .font(.footnote)
            .foregroundStyle(.brand)
        }
        .buttonStyle(.plain)

        Text(.legalGateAgreement)
          .font(.caption2)
          .foregroundStyle(.textSecondary)
          .multilineTextAlignment(.center)
      }
      .padding(.top, 4)
    }
    .padding(24)
    .frame(maxWidth: 440)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(AppColors.Background.background.ignoresSafeArea())
    .interactiveDismissDisabled(true)
    .sheet(item: $safariURL) { identifiableURL in
      SafariView(url: identifiableURL.url)
    }
  }
}

#if DEBUG
#Preview {
  LegalGateView {}
}
#endif
