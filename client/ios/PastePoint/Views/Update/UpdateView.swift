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
  @Environment(\.dismiss) private var dismiss
  @State private var sheetHeight: CGFloat = 400

  private var isRequired: Bool { kind == .required }

  var body: some View {
    if isRequired {
      content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.Background.background.ignoresSafeArea())
        .interactiveDismissDisabled(true)
    } else {
      NavigationStack {
        content
          .frame(maxWidth: .infinity)
          .fixedSize(horizontal: false, vertical: true)
          .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
          } action: { height in
            guard height > 0 else { return }
            sheetHeight = height + 56
          }
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .topBarTrailing) { closeButton }
          }
      }
      .presentationDetents([.height(sheetHeight)])
      .presentationDragIndicator(.visible)
      .presentationBackground(AppColors.Background.background)
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

  @ViewBuilder
  private var closeButton: some View {
    if #available(iOS 26, *) {
      Button(role: .close) { dismiss() }
    } else {
      Button { dismiss() } label: {
        ZStack {
          Circle()
            .fill(Color(UIColor.tertiarySystemFill))
            .frame(width: 36, height: 36)
          Image(systemName: "xmark")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(Color(UIColor.secondaryLabel))
        }
        .contentShape(Circle())
      }
      .buttonStyle(.plain)
    }
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
