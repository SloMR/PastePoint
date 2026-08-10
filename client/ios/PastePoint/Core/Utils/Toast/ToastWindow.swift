//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI
import UIKit

// MARK: - Pass-through Window

/// Sits above the sheet/alert layer and lets touches fall through, except on a toast.
final class PassthroughWindow: UIWindow {
  var interactiveRect: CGRect = .zero

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard interactiveRect.contains(point) else { return nil }
    return super.hitTest(point, with: event)
  }
}

// MARK: - Host

private final class ToastHostingController: UIHostingController<ToastOverlayView> {
  var hidesStatusBar = false {
    didSet {
      guard hidesStatusBar != oldValue else { return }
      setNeedsStatusBarAppearanceUpdate()
    }
  }

  override var prefersStatusBarHidden: Bool { hidesStatusBar }
}

// MARK: - Presenter

/// Owns the overlay window for the lifetime of the app root so it isn't released.
@MainActor
final class ToastPresenter {
  private var window: PassthroughWindow?

  func install(in scene: UIWindowScene, center: ToastCenter) {
    guard window == nil else { return }

    let window = PassthroughWindow(windowScene: scene)
    let host = ToastHostingController(rootView: ToastOverlayView(center: center))
    host.rootView.onFrameChange = { [weak window] rect in window?.interactiveRect = rect }
    host.rootView.onDockedChange = { [weak host] docked in host?.hidesStatusBar = docked }
    host.view.backgroundColor = .clear

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

/// Reports the `UIWindowScene` once the view is in the hierarchy.
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
  /// Installs the global toast overlay window (above sheets) bound to `center`.
  func toastWindow(center: ToastCenter, style: UIUserInterfaceStyle) -> some View {
    modifier(ToastWindowModifier(center: center, style: style))
  }
}
