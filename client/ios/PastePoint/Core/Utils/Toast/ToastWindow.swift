//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI
import UIKit

// MARK: - Pass-through Window

/// A transparent window that sits above the sheet/alert layer and lets touches
/// fall through to the app below — except where they land on a toast row.
final class PassthroughWindow: UIWindow {
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard let hit = super.hitTest(point, with: event) else { return nil }
    // Empty areas resolve to the hosting controller's root view → pass through.
    return hit === rootViewController?.view ? nil : hit
  }
}

// MARK: - Presenter

/// Owns the overlay window for the lifetime of the app root so it isn't released.
@MainActor
final class ToastPresenter {
  private var window: PassthroughWindow?

  func install(in scene: UIWindowScene, center: ToastCenter) {
    guard window == nil else { return }

    let host = UIHostingController(rootView: ToastOverlayView(center: center))
    host.view.backgroundColor = .clear

    let window = PassthroughWindow(windowScene: scene)
    window.rootViewController = host
    window.windowLevel = .alert + 1
    window.isHidden = false
    self.window = window
  }

  func setStyle(_ style: UIUserInterfaceStyle) {
    window?.overrideUserInterfaceStyle = style
  }
}

// MARK: - Scene Finder

/// Reports the `UIWindowScene` once the view is in the hierarchy so the overlay
/// window can be attached to the active scene.
private struct WindowSceneFinder: UIViewRepresentable {
  let onScene: (UIWindowScene) -> Void

  func makeUIView(context _: Context) -> UIView {
    UIView()
  }

  func updateUIView(_ uiView: UIView, context _: Context) {
    if let scene = uiView.window?.windowScene {
      onScene(scene)
    }
  }
}

// MARK: - Modifier

private struct ToastWindowModifier: ViewModifier {
  let center: ToastCenter
  let style: UIUserInterfaceStyle

  @State private var presenter = ToastPresenter()

  func body(content: Content) -> some View {
    content
      .background(
        WindowSceneFinder { scene in
          presenter.install(in: scene, center: center)
          presenter.setStyle(style)
        },
      )
      .onChange(of: style) { _, newStyle in
        presenter.setStyle(newStyle)
      }
  }
}

extension View {
  /// Installs the global toast overlay window (above sheets) bound to `center`,
  /// matching the app's resolved light/dark `style`.
  func toastWindow(center: ToastCenter, style: UIUserInterfaceStyle) -> some View {
    modifier(ToastWindowModifier(center: center, style: style))
  }
}
