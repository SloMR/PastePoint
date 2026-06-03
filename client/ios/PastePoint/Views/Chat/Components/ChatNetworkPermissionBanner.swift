//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct NetworkPermissionBanner: View {
  var onDismiss: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "network.slash")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(.white)

      VStack(alignment: .leading, spacing: 2) {
        Text("Unable to connect")
          .font(.subheadline).fontWeight(.semibold)
          .foregroundStyle(.white)
        Button {
          guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
          UIApplication.shared.open(url)
        } label: {
          Text("Check local network permissions in Settings →")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.85))
            .underline()
        }
        .buttonStyle(.plain)
      }

      Spacer()

      Button { onDismiss() } label: {
        Image(systemName: "xmark")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(.white.opacity(0.8))
          .frame(width: 28, height: 28)
          .background(.white.opacity(0.15), in: Circle())
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(Color.orange.opacity(0.9))
    .transition(.move(edge: .top).combined(with: .opacity))
    .animation(.easeInOut(duration: 0.3), value: true)
  }
}
