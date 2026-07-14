//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct SettingsFooterView: View {
  @Binding var safariURL: IdentifiableURL?

  private struct SocialLink {
    let icon: String
    let name: String
    let url: URL
  }

  private var socialLinks: [SocialLink] {
    [
      ("linkedin", "LinkedIn", "https://www.linkedin.com/in/sulaiman-alromaih-845700202/"),
      ("github", "GitHub", "https://github.com/SloMR/pastepoint"),
      ("x", "X", "https://x.com/PastePoint"),
      ("instagram", "Instagram", "https://www.instagram.com/paste_point/"),
    ].compactMap { icon, name, urlString in
      URL(string: urlString).map { SocialLink(icon: icon, name: name, url: $0) }
    }
  }

  private func socialLink(_ link: SocialLink) -> some View {
    Button {
      safariURL = IdentifiableURL(url: link.url)
    } label: {
      Image(link.icon)
        .renderingMode(.template)
        .resizable()
        .scaledToFit()
        .frame(width: 16, height: 16)
        .foregroundStyle(.textSecondary)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(verbatim: link.name))
  }

  var body: some View {
    VStack(spacing: 10) {
      // Social links
      HStack(alignment: .center, spacing: 20) {
        ForEach(socialLinks, id: \.icon) { socialLink($0) }
      }

      // privacy · version
      HStack(spacing: 6) {
        Button {
          if let url = URL(string: AppEnvironment.legalUrl) {
            safariURL = IdentifiableURL(url: url)
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
    .sheet(item: $safariURL) { identifiableURL in
      SafariView(url: identifiableURL.url)
    }
  }
}
