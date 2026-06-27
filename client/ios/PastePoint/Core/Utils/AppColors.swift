//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

// MARK: - AppColors

enum AppColors {

  enum Brand {
    static let brand = Color("brand")
    static let accent = Color("brandAccent")
  }

  enum Text {
    static let primary = Color("textPrimary")
    static let secondary = Color("textSecondary")
    static let muted = Color("textMuted")
  }

  enum Background {
    static let background = Color("background")
    static let surface = Color("surface")
    static let contentArea = Color("contentArea")
    static let stepCard = Color("stepCard")
    static let message = Color("messageBackground")
    static let input = Color("inputBackground")
  }

  enum Border {
    static let border = Color("border")
    static let button = Color("borderButton")
  }

  enum Primary {
    static let p100 = Color("primary100")
    static let p300 = Color("primary300")
  }

  enum Gray {
    static let g300 = Color("gray300")
    static let g400 = Color("gray400")
    static let g600 = Color("gray600")
    static let g700 = Color("gray700")
    static let g800 = Color("gray800")
    static let g900 = Color("gray900")
  }

  enum Status {
    static let danger = Color("danger")
    static let success = Color("success")
    static let warning = Color("warning")
    static let info = Color("info")
  }

  enum QR {
    static let background = Color("qrBackground")
    static let accent = Color("qrAccent")
    static let hover = Color("qrHover")
  }

  enum Scrollbar {
    static let track = Color("scrollbarTrack")
    static let thumb = Color("scrollbarThumb")
  }

  enum Scheme {
    static let storageKey = "appColorScheme"
    static let `default` = "light"

    static func colorScheme(from raw: String) -> ColorScheme {
      raw == "dark" ? .dark : .light
    }

    static func next(after current: String) -> String {
      current == "light" ? "dark" : "light"
    }
  }
}
