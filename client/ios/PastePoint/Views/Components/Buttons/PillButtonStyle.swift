//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct PillButtonStyle: ButtonStyle {
  enum Variant { case filled, outlined }

  var variant: Variant = .filled
  var tint: Color = AppColors.Brand.brand
  var fullWidth: Bool = true

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .fontWeight(.semibold)
      .frame(maxWidth: fullWidth ? .infinity : nil)
      .padding(.vertical, 14)
      .foregroundStyle(variant == .filled ? Color.white : tint)
      .background(variant == .filled ? tint : Color.clear, in: Capsule())
      .overlay {
        if variant == .outlined {
          Capsule().stroke(tint, lineWidth: 1.5)
        }
      }
      .contentShape(Capsule())
      .opacity(configuration.isPressed ? 0.85 : 1)
  }
}

extension ButtonStyle where Self == PillButtonStyle {
  static func pill(
    _ variant: PillButtonStyle.Variant = .filled,
    tint: Color = AppColors.Brand.brand,
    fullWidth: Bool = true,
  ) -> PillButtonStyle {
    PillButtonStyle(variant: variant, tint: tint, fullWidth: fullWidth)
  }
}
