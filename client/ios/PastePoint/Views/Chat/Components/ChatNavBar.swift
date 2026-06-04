//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Logging
import SwiftUI

struct ChatNavBar: View {
  @Environment(\.colorScheme) private var colorScheme
  private let logger = Logger(label: "ChatNavBar")

  var onMenuTap: (() -> Void)?
  var onThemeTap: (() -> Void)?

  var body: some View {
    HStack {
      // Logo
      Image("pastepoint")
        .resizable()
        .scaledToFit()
        .frame(height: 32)

      Spacer()

      HStack(spacing: 10) {

        // Language
        // TODO: Implement language switching; add toast = .success("Language changed") on change
        Button("AR") {
          logger.info("Language Button Clicked")
        }
        .foregroundStyle(.brand)
        .font(.headline)
        .frame(width: 36, height: 36)
        .overlay(
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(.border, lineWidth: 1),
        )
        .buttonStyle(.plain)

        // Theme
        Button {
          onThemeTap?()
        } label: {
          Image(systemName: colorScheme == .dark ? "sun.max.fill" : "moon")
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.textPrimary)
            .frame(width: 36, height: 36)
            .overlay(
              RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.border, lineWidth: 1),
            )
        }
        .buttonStyle(.plain)

        // Menu
        Button {
          onMenuTap?()
        } label: {
          Image(systemName: "line.3.horizontal")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.textPrimary)
            .frame(width: 36, height: 36)
            .overlay(
              RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.border, lineWidth: 1),
            )
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 16)
    .padding(.top, 6)
    .padding(.bottom, 10)
    .background(AppColors.Background.background)
  }
}

// MARK: - Preview

#if DEBUG
#Preview {
  ChatNavBar()
}
#endif
