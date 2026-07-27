//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct WelcomeCard<Footer: View>: View {
  private let title: LocalizedStringResource
  private let message: LocalizedStringResource
  private let footer: Footer

  init(
    title: LocalizedStringResource,
    message: LocalizedStringResource,
    @ViewBuilder footer: () -> Footer,
  ) {
    self.title = title
    self.message = message
    self.footer = footer()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.subheadline)
        .fontWeight(.semibold)
        .foregroundStyle(.textPrimary)
        .multilineTextAlignment(.leading)

      Text(message)
        .font(.caption)
        .foregroundStyle(.textSecondary)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)

      footer
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(AppColors.Background.stepCard, in: RoundedRectangle(cornerRadius: 10))
  }
}

extension WelcomeCard where Footer == EmptyView {
  init(title: LocalizedStringResource, message: LocalizedStringResource) {
    self.init(title: title, message: message) { EmptyView() }
  }
}

// MARK: - Preview

#if DEBUG
#Preview {
  PreviewStage {
    VStack(spacing: 10) {
      WelcomeCard(title: .optionSameWifiTitle, message: .optionSameWifiBody)
      WelcomeCard(title: .optionElsewhereTitle, message: .optionElsewhereBody) {
        CreateInviteButton()
      }
    }
    .padding()
    .environmentObject(AppServices.preview)
    .environmentObject(ToastCenter())
  }
}
#endif
