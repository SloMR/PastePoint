//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct StatusBanner<Leading: View>: View {
  let tint: Color
  let title: String
  var message: String?
  var actionTitle: String?
  var onAction: (() -> Void)?
  var onDismiss: (() -> Void)?
  @ViewBuilder var leading: () -> Leading

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      leading()
        .frame(width: 22, height: 22)

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundStyle(AppColors.Text.primary)

        if let message {
          Text(message)
            .font(.footnote)
            .foregroundStyle(AppColors.Text.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        if let actionTitle, let onAction {
          Button(action: onAction) {
            Text(actionTitle)
              .font(.footnote)
              .fontWeight(.semibold)
              .foregroundStyle(tint)
              .underline()
          }
          .buttonStyle(.plain)
          .padding(.top, 1)
        }
      }

      Spacer(minLength: 8)

      if let onDismiss {
        Button(action: onDismiss) {
          Image(systemName: "xmark")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(AppColors.Text.secondary)
            .frame(width: 26, height: 26)
            .background(AppColors.Text.primary.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 11)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(tint.opacity(0.12)),
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(tint.opacity(0.22), lineWidth: 1),
    )
    .padding(.horizontal, 12)
    .padding(.top, 8)
    .transition(.move(edge: .top).combined(with: .opacity))
  }
}

#if DEBUG
#Preview {
  PreviewStage(alignment: .top) {
    VStack(spacing: 0) {
      StatusBanner(
        tint: AppColors.Status.danger,
        title: "Local network access is off",
        message: "PastePoint needs it to find people nearby.",
        actionTitle: "Open Settings",
        onAction: {},
        onDismiss: {},
        leading: {
          Image(systemName: "wifi.slash")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(AppColors.Status.danger)
        },
      )

      StatusBanner(
        tint: AppColors.Status.warning,
        title: "Still connecting…",
        message: "Some members aren't reachable yet.",
        onDismiss: {},
        leading: {
          Circle()
            .fill(AppColors.Status.warning)
            .frame(width: 9, height: 9)
        },
      )
    }
  }
}
#endif
