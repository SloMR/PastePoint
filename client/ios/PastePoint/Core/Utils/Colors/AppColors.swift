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
  }

  enum Background {
    static let background = Color("background")
    static let surface = Color("surface")
    static let stepCard = Color("stepCard")
    static let input = Color("inputBackground")
  }

  enum Primary {
    static let p300 = Color("primary300")
  }

  enum Status {
    static let danger = Color("danger")
    static let success = Color("success")
    static let warning = Color("warning")
    static let info = Color("info")
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
