//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

/// Update prompt for both modes: `.required` is a blocking full-screen gate,
/// `.optional` is a dismissible sheet. Shared content, different chrome.
struct UpdateView: View {
  enum Kind { case required, optional }

  let kind: Kind
  let storeURL: URL
  var latest: String?

  @Environment(\.openURL) private var openURL

  private var isRequired: Bool { kind == .required }

  var body: some View {
    if isRequired {
      content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.Background.background.ignoresSafeArea())
        .interactiveDismissDisabled(true)
    } else {
      content
        .sheetContainer(initialHeight: 400)
    }
  }

  private var content: some View {
    VStack(spacing: 20) {
      ZStack {
        Circle()
          .fill(AppColors.Brand.accent.opacity(0.12))
          .frame(width: 104, height: 104)

        Image(systemName: "arrow.down.circle.fill")
          .resizable()
          .scaledToFit()
          .frame(width: 56, height: 56)
          .foregroundStyle(AppColors.Brand.accent)
      }

      VStack(spacing: 10) {
        Text(isRequired ? .updateRequiredTitle : .updateAvailableTitle)
          .font(.title2.bold())
          .foregroundStyle(.textPrimary)
          .multilineTextAlignment(.center)

        Text(isRequired ? .updateRequiredMessage : .updateAvailableMessage(latest ?? ""))
          .font(.body)
          .foregroundStyle(.textSecondary)
          .multilineTextAlignment(.center)
      }
      .padding(.horizontal)

      Button {
        openURL(storeURL)
      } label: {
        Text(.updateAction)
          .font(.headline)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 6)
      }
      .buttonStyle(.borderedProminent)
      .tint(AppColors.Brand.accent)
      .padding(.top, 4)
    }
    .padding(24)
  }
}

#if DEBUG
#Preview("Required") {
  // swiftlint:disable:next force_unwrapping
  UpdateView(kind: .required, storeURL: URL(string: "https://apps.apple.com")!)
}

#Preview("Optional") {
  Color.clear.sheet(isPresented: .constant(true)) {
    // swiftlint:disable:next force_unwrapping
    UpdateView(kind: .optional, storeURL: URL(string: "https://apps.apple.com")!, latest: "0.8.3")
  }
}
#endif
