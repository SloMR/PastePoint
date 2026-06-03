//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct SettingsFooterView: View {
  @Binding var privacyURLToShow: IdentifiableURL?

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .center, spacing: 6) {
        Image("linkedin")
          .renderingMode(.template)
          .resizable()
          .scaledToFit()
          .frame(width: 16, height: 16)
          .padding(.trailing, 5)
          .foregroundStyle(.brand)

        Image("github")
          .renderingMode(.template)
          .resizable()
          .scaledToFit()
          .frame(width: 16, height: 16)
          .padding(.trailing, 5)
          .foregroundStyle(.brand)

        Image("x")
          .renderingMode(.template)
          .resizable()
          .scaledToFit()
          .frame(width: 16, height: 16)
          .padding(.trailing, 5)
          .foregroundStyle(.brand)

        Image("instagram")
          .renderingMode(.template)
          .resizable()
          .scaledToFit()
          .frame(width: 16, height: 16)
          .padding(.trailing, 5)
          .foregroundStyle(.brand)
      }

      Button {
        if let url = URL(string: "https://pastepoint.com/privacy") {
          privacyURLToShow = IdentifiableURL(url: url)
        }
      } label: {
        HStack(spacing: 2) {
          Text("Privacy & Terms")
            .font(.caption2)
            .foregroundColor(.brand)

          Image("privacy.and.terms")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 12, height: 12)
            .foregroundStyle(.brand)
        }
        .fontWeight(.bold)
      }
      .buttonStyle(.plain)
      .padding(.vertical, 6)

      Text("Version \(Bundle.main.appVersion)")
        .font(.caption2)
        .foregroundColor(.textPrimary)
        .padding(.vertical, 4)

      Text("© 2026 PastePoint. All rights reserved.")
        .font(.caption2)
        .foregroundColor(.textPrimary)
        .padding(.vertical, 4)
    }
    .sheet(item: $privacyURLToShow) { identifiableURL in
      SafariView(url: identifiableURL.url)
    }
  }
}
