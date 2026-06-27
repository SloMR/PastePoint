//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct SettingsFooterView: View {
  @Binding var privacyURLToShow: IdentifiableURL?

  private func socialIcon(_ name: String) -> some View {
    Image(name)
      .renderingMode(.template)
      .resizable()
      .scaledToFit()
      .frame(width: 16, height: 16)
      .foregroundStyle(.textSecondary)
  }

  var body: some View {
    VStack(spacing: 10) {
      // Social links
      HStack(alignment: .center, spacing: 20) {
        socialIcon("linkedin")
        socialIcon("github")
        socialIcon("x")
        socialIcon("instagram")
      }

      // privacy · version
      HStack(spacing: 6) {
        Button {
          if let url = URL(string: AppEnvironment.legalUrl) {
            privacyURLToShow = IdentifiableURL(url: url)
          }
        } label: {
          Text(.privacyAndTerms)
            .font(.caption2)
            .foregroundColor(.brand)
        }
        .buttonStyle(.plain)

        Text(verbatim: "·")
          .font(.caption2)
          .foregroundColor(.textSecondary)

        Text(.appVersion(Bundle.main.appVersion))
          .font(.caption2)
          .foregroundColor(.textSecondary)
      }

      Text(.copyrightNotice)
        .font(.caption2)
        .foregroundColor(.textSecondary)
        .multilineTextAlignment(.center)
    }
    .sheet(item: $privacyURLToShow) { identifiableURL in
      SafariView(url: identifiableURL.url)
    }
  }
}
