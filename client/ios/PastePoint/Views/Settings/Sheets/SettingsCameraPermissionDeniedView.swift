//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct CameraPermissionDeniedView: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ZStack(alignment: .topTrailing) {
      Color.black.ignoresSafeArea()

      closeButton(tint: .white, background: .white.opacity(0.2))

      VStack(spacing: 20) {
        Image(systemName: "camera.fill")
          .font(.system(size: 52))
          .foregroundStyle(.white.opacity(0.5))

        VStack(spacing: 8) {
          Text("Camera Access Required")
            .font(.title3).fontWeight(.semibold)
            .foregroundStyle(.white)

          Text("PastePoint needs camera access to scan QR codes. Enable it in Settings.")
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.65))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
        }

        Button { CameraPermission.openSettings() } label: {
          Text("Open Settings")
            .fontWeight(.semibold)
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(AppColors.Brand.brand, in: Capsule())
        }
        .buttonStyle(.plain)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  func closeButton(tint: Color, background: Color) -> some View {
    Button { dismiss() } label: {
      ZStack {
        Circle()
          .fill(background)
          .frame(width: 36, height: 36)
        Image(systemName: "xmark")
          .font(.system(size: 13, weight: .bold, design: .rounded))
          .foregroundStyle(tint)
      }
      .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .padding(.horizontal)
    .padding(.top, 56)
  }
}
