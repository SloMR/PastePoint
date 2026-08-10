//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI
import UIKit

// MARK: - Cutout

/// Housing geometry in points, portrait only. `nonisolated` so `DockShape` can read it.
nonisolated struct ToastCutout {
  static let cardRadius: CGFloat = 26

  let top: CGFloat
  let size: CGSize
  let housingRadius: CGFloat
  let contentTop: CGFloat
  let minWidth: CGFloat
  let maxWidth: CGFloat

  static let island = Self(
    top: 11,
    size: CGSize(width: 125, height: 36),
    housingRadius: 18,
    contentTop: 47,
    minWidth: 168,
    maxWidth: 344,
  )

  static let notch = Self(
    top: 0,
    size: CGSize(width: 162, height: 32),
    housingRadius: 20,
    contentTop: 42,
    minWidth: 206,
    maxWidth: 340,
  )

  func radii(_ radius: CGFloat) -> RectangleCornerRadii {
    let topRadius = top == 0 ? 0 : radius
    return RectangleCornerRadii(
      topLeading: topRadius,
      bottomLeading: radius,
      bottomTrailing: radius,
      topTrailing: topRadius,
    )
  }

  /// `nil` when there is no housing (SE, iPad, landscape). iPad is excluded by idiom rather
  /// than by inset, because its 32pt top would pass for a notch. Measure a `UIWindow`: the
  /// overlay ignores the safe area, so a `GeometryReader` inside it always reads zero.
  @MainActor
  static func current() -> Self? {
    guard UIDevice.current.userInterfaceIdiom == .phone else { return nil }

    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    guard
      let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first,
      scene.interfaceOrientation.isPortrait,
      let window = scene.keyWindow ?? scene.windows.first
    else { return nil }

    switch window.safeAreaInsets.top {
    case 51...: return .island
    case 30..<51: return .notch
    default: return nil
    }
  }
}

// MARK: - Reveal Shape

private nonisolated struct DockShape: Shape {
  let cutout: ToastCutout
  var progress: CGFloat

  var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }

  func path(in rect: CGRect) -> Path {
    let width = max(0, lerp(cutout.size.width, rect.width, progress))
    let height = max(0, lerp(cutout.size.height, rect.height, progress))
    let box = CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: height)

    // Radius tracks height, so a short card stays as round as the housing.
    let radius = min(ToastCutout.cardRadius, height * cutout.housingRadius / cutout.size.height)

    return UnevenRoundedRectangle(cornerRadii: cutout.radii(radius), style: .continuous)
      .path(in: box)
  }
}

private nonisolated func lerp(_ from: CGFloat, _ to: CGFloat, _ progress: CGFloat) -> CGFloat {
  from + (to - from) * progress
}

// MARK: - Docked Toast

/// A black card grown out of the Dynamic Island or notch, sized to its message. It stays black
/// in both appearances so it looks welded to the cutout; the status colour lives in the icon.
struct DockedToastView: View {
  private static let retractDuration = 0.22

  private static let barDelay = 0.2

  let toast: ToastItem
  let cutout: ToastCutout
  let onDismiss: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.layoutDirection) private var layoutDirection

  @State private var revealed = false
  @State private var contentShown = false
  @State private var barShown = false
  @State private var drained = false
  @State private var dismissing = false

  var body: some View {
    ViewThatFits(in: .horizontal) {
      card.fixedSize(horizontal: true, vertical: false)
      card
    }
    .frame(maxWidth: cutout.maxWidth)
    .onTapGesture(perform: retract)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isButton)
    .accessibilityAction { retract() }
    // Start on the next turn: a state change made inside `onAppear` lands together with
    // the insertion, so the card is drawn already grown and never animates.
    .onAppear { Task { start() } }
    .task {
      try? await Task.sleep(for: .seconds(ToastCenter.displayDuration))
      guard !Task.isCancelled else { return }
      retract()
    }
  }

  private func start() {
    guard !reduceMotion else {
      revealed = true
      contentShown = true
      barShown = true
      withAnimation(.linear(duration: ToastCenter.displayDuration)) { drained = true }
      return
    }

    withAnimation(.spring(response: 0.44, dampingFraction: 0.68)) { revealed = true }
    withAnimation(.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.28).delay(0.06)) { contentShown = true }
    withAnimation(.easeInOut(duration: 0.3).delay(Self.barDelay)) { barShown = true }
    withAnimation(.linear(duration: ToastCenter.displayDuration - Self.barDelay).delay(Self.barDelay)) { drained = true }
  }

  private func retract() {
    guard !dismissing else { return }
    dismissing = true

    guard !reduceMotion else { return onDismiss() }

    withAnimation(.timingCurve(0.34, 0.9, 0.3, 1, duration: Self.retractDuration)) {
      revealed = false
      contentShown = false
      barShown = false
    }

    Task {
      try? await Task.sleep(for: .seconds(Self.retractDuration))
      onDismiss()
    }
  }

  private var card: some View {
    HStack(spacing: 10) {
      ZStack {
        Circle()
          .fill(toast.style.color)
          .frame(width: 28, height: 28)

        Image(systemName: toast.style.icon)
          .font(.system(size: 13, weight: .bold, design: .rounded))
          .foregroundStyle(.white)
      }

      Text(toast.message)
        .font(.system(size: 14, weight: .medium, design: .rounded))
        .foregroundStyle(.white.opacity(0.94))
        .lineLimit(3)
        .fixedSize(horizontal: false, vertical: true)
    }
    .opacity(contentShown ? 1 : 0)
    .scaleEffect(revealed ? 1 : 0.86, anchor: .top)
    .padding(.top, cutout.contentTop)
    .padding(.horizontal, 16)
    .padding(.bottom, 12)
    .frame(minWidth: cutout.minWidth)
    .background { surface }
    // Mask the message too, or the card's edge just sweeps across text already sitting there.
    .mask { dock }
    .compositingGroup()
    .shadow(color: .black.opacity(revealed ? 0.45 : 0), radius: 20, x: 0, y: 18)
  }

  private var surface: some View {
    Color.black
      .overlay(alignment: .bottom) {
        Rectangle()
          .fill(toast.style.color)
          .frame(height: 2)
          .scaleEffect(x: drained ? 0 : 1, anchor: drainAnchor)
          .opacity(barShown ? 0.85 : 0)
      }
      .overlay { dock.stroke(.white.opacity(revealed ? 0.07 : 0), lineWidth: 2) }
  }

  private var dock: DockShape {
    DockShape(cutout: cutout, progress: revealed ? 1 : 0)
  }

  /// `UnitPoint` is a raw geometric point, so unlike `Alignment` it needs flipping for RTL.
  private var drainAnchor: UnitPoint {
    UnitPoint(x: layoutDirection == .rightToLeft ? 1 : 0, y: 0.5)
  }
}

#if DEBUG

// MARK: - Preview

private struct DockedToastPreview: View {
  let cutout: ToastCutout
  let toast: ToastItem

  /// Replays the entrance instead of leaving the canvas blank after one lifetime.
  @State private var generation = 0

  var body: some View {
    DockedToastView(toast: toast, cutout: cutout) { generation += 1 }
      .id(generation)
      .padding(.top, cutout.top)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .background(AppColors.Background.background)
      .overlay(alignment: .top) {
        UnevenRoundedRectangle(cornerRadii: cutout.radii(cutout.housingRadius), style: .continuous)
          .fill(.black)
          .frame(width: cutout.size.width, height: cutout.size.height)
          .padding(.top, cutout.top)
      }
      .ignoresSafeArea()
  }
}

#Preview("Island · short") {
  DockedToastPreview(cutout: .island, toast: .success(.codeCopied))
}

#Preview("Island · wrapping") {
  DockedToastPreview(cutout: .island, toast: .error(.startPrivateFailed))
}

#Preview("Notch") {
  DockedToastPreview(cutout: .notch, toast: .info(.roomJoined("General")))
}
#endif
