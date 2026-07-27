//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct WelcomeFeatureGrid: View {
  private static let features: [(String, LocalizedStringResource)] = [
    ("lock", .featureEncrypted),
    ("icloud.slash", .featureNoCloud),
    ("doc", .featureAnyFile),
    ("person.slash", .featureNoAccount),
    ("arrow.up.arrow.down", .featureLocalSpeed),
    ("chevron.left.slash.chevron.right", .featureFree),
  ]

  var body: some View {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
      ForEach(Self.features, id: \.0) { icon, label in
        cell(icon: icon, label: label)
      }
    }
  }

  private func cell(icon: String, label: LocalizedStringResource) -> some View {
    HStack(spacing: 8) {
      Image(systemName: icon)
        .font(.caption)
        .foregroundStyle(.textPrimary)
        .frame(width: 20, alignment: .center)
        .accessibilityHidden(true)
      Text(label)
        .font(.caption)
        .foregroundStyle(.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(AppColors.Background.stepCard, in: RoundedRectangle(cornerRadius: 10))
  }
}

// MARK: - Preview

#if DEBUG
#Preview {
  PreviewStage {
    WelcomeFeatureGrid()
      .padding()
  }
}
#endif
