//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct WelcomeView: View {
  @EnvironmentObject private var services: AppServices

  private var isPrivate: Bool {
    services.wsService.currentSessionCode != nil
  }

  private let features: [(String, LocalizedStringResource)] = [
    ("lock", .featureEncrypted),
    ("icloud.slash", .featureNoCloud),
    ("doc", .featureAnyFile),
    ("person.slash", .featureNoAccount),
    ("arrow.up.arrow.down", .featureLocalSpeed),
    ("chevron.left.slash.chevron.right", .featureFree),
  ]

  var body: some View {
    // Centers the content vertically when it fits, scrolls when it doesn't.
    GeometryReader { geometry in
      ScrollView {
        welcomeContent
          .padding(.vertical, 32)
          .frame(maxWidth: 480)
          .frame(maxWidth: .infinity, minHeight: geometry.size.height)
      }
    }
  }

  private var welcomeContent: some View {
    VStack(alignment: .center, spacing: 20) {

      // Room icon
      Group {
        if isPrivate {
          Image("lock.light")
            .resizable()
            .scaledToFit()
            .frame(width: 28, height: 28)
        } else {
          Image("users")
            .resizable()
            .scaledToFit()
            .frame(width: 28, height: 28)
        }
      }
      .padding(18)
      .background(Circle().fill(.brand))

      // Title + subtitle
      VStack(spacing: 6) {
        Text(isPrivate ? .privateRoom : .publicRoom)
          .font(.title2)
          .fontWeight(.bold)
          .foregroundStyle(.textPrimary)

        Text(isPrivate ? .privateSessionInfo : .publicSessionInfo)
          .font(.subheadline)
          .foregroundStyle(.textSecondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 16)
      }

      // Steps
      VStack(spacing: 12) {
        Text(.whatToDoNext)
          .font(.caption)
          .fontWeight(.semibold)
          .foregroundStyle(.textSecondary)
          .textCase(.uppercase)
          .tracking(0.5)

        if isPrivate {
          WelcomeStepList(steps: [
            .shareSessionCode,
            .waitForMembers,
            .startChatting,
          ])
        } else {
          WelcomeStepList(steps: [
            .inviteOthersPublic,
            .startConversation,
          ])
        }
      }
      .padding(.horizontal, 16)

      // Features grid
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
        ForEach(features, id: \.0) { icon, label in
          featureCell(icon: icon, label: label)
        }
      }
      .padding(.horizontal, 16)

      // Dots
      HStack(spacing: 8) {
        Circle().fill(.brand.opacity(0.47)).frame(width: 8, height: 8)
        Circle().fill(.brand.opacity(0.47)).frame(width: 8, height: 8)
        Circle().fill(.brand.opacity(0.47)).frame(width: 8, height: 8)
      }
      .padding(.bottom, 8)
    }
  }

  private func featureCell(icon: String, label: LocalizedStringResource) -> some View {
    HStack(spacing: 8) {
      Image(systemName: icon)
        .font(.system(size: 13))
        .foregroundStyle(.textPrimary)
        .frame(width: 20, alignment: .center)
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
  WelcomeView()
    .environmentObject(AppServices.preview)
}
#endif
