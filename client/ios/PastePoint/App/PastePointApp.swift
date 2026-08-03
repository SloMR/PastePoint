//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI
import UIKit

@main
struct PastePointApp: App {
  @Environment(\.scenePhase) private var phase
  @AppStorage(AppColors.Scheme.storageKey) private var colorSchemeRaw: String = AppColors.Scheme.default
  @State private var didRequestLocalNetwork = false

  @StateObject private var services = AppServices.shared
  @StateObject private var toast = ToastCenter()

  init() {
    AppLogging.bootstrap()
    SettingsBundle.syncVersion()
  }

  /// Resolved light/dark for the toast overlay window, which lives outside the
  /// SwiftUI tree and so doesn't inherit `.preferredColorScheme`.
  private var toastStyle: UIUserInterfaceStyle {
    switch AppColors.Scheme.colorScheme(from: colorSchemeRaw) {
    case .dark: .dark
    case .light: .light
    default: .unspecified
    }
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(services)
        .environmentObject(toast)
        .toastWindow(center: toast, style: toastStyle)
    }
    .onChange(of: phase) { _, newPhase in
      switch newPhase {

      case .active:
        if !didRequestLocalNetwork {
          didRequestLocalNetwork = true
          LocalNetworkPermission.requestAccess()
        }
        Task { await services.handleForeground() }
        Task { await services.updateService.check() }

      case .background:
        services.handleBackground()

      case .inactive:
        break

      @unknown default:
        break
      }
    }
  }
}
