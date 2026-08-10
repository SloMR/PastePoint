//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

// MARK: - Toast Style

enum ToastStyle {
  case success
  case error
  case warning
  case info

  var icon: String {
    switch self {
    case .success: "checkmark"
    case .error: "xmark"
    case .warning: "exclamationmark"
    case .info: "info"
    }
  }

  var color: Color {
    switch self {
    case .success: AppColors.Status.success
    case .error: AppColors.Status.danger
    case .warning: AppColors.Status.warning
    case .info: AppColors.Status.info
    }
  }
}

// MARK: - Toast Item

struct ToastItem: Identifiable, Equatable {
  var id = UUID()
  let message: LocalizedStringResource
  let style: ToastStyle

  static func success(_ message: LocalizedStringResource) -> Self { .init(message: message, style: .success) }
  static func error(_ message: LocalizedStringResource) -> Self { .init(message: message, style: .error) }
  static func warning(_ message: LocalizedStringResource) -> Self { .init(message: message, style: .warning) }
  static func info(_ message: LocalizedStringResource) -> Self { .init(message: message, style: .info) }
}

// MARK: - Individual Toast Row

private struct ToastRowView: View {
  let toast: ToastItem
  let onDismiss: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      ZStack {
        Circle()
          .fill(toast.style.color)
          .frame(width: 30, height: 30)

        Image(systemName: toast.style.icon)
          .font(.system(size: 13, weight: .bold, design: .rounded))
          .foregroundStyle(.white)
      }

      Text(toast.message)
        .font(.system(size: 14, weight: .medium, design: .rounded))
        .foregroundStyle(.primary)
        .lineLimit(2)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.leading, 8)
    .padding(.trailing, 16)
    .padding(.vertical, 10)
    .background {
      Capsule(style: .continuous)
        .fill(.regularMaterial)
        .overlay {
          Capsule(style: .continuous)
            .strokeBorder(
              LinearGradient(
                colors: [.white.opacity(0.25), .white.opacity(0.04)],
                startPoint: .top,
                endPoint: .bottom,
              ),
              lineWidth: 0.5,
            )
        }
        .shadow(color: .black.opacity(0.14), radius: 22, x: 0, y: 10)
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
    }
    .frame(maxWidth: 400)
    .onTapGesture { onDismiss() }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isButton)
    .accessibilityAction { onDismiss() }
    .task {
      try? await Task.sleep(for: .seconds(ToastCenter.displayDuration))
      guard !Task.isCancelled else { return }
      onDismiss()
    }
  }
}

// MARK: - Toast Overlay

/// Draws the toast queue in the global overlay window (see `ToastWindow`), above sheets and
/// everything else. The first toast docks to the Island or notch if the device has one.
struct ToastOverlayView: View {
  @ObservedObject var center: ToastCenter

  var onFrameChange: (CGRect) -> Void = { _ in }

  var onDockedChange: (Bool) -> Void = { _ in }

  var body: some View {
    Group {
      if let cutout = center.cutout, let head = center.items.first {
        stack(top: cutout.top) {
          DockedToastView(toast: head, cutout: cutout) { dismiss(head.id) }
            .id(head.id)
            .transition(.identity)

          capsules(Array(center.items.dropFirst()))
        }
        .ignoresSafeArea(edges: .top)
      } else {
        stack(top: 8) { capsules(center.items) }
      }
    }
    .onChange(of: center.isDocked, initial: true) { _, docked in onDockedChange(docked) }
  }

  private func stack(top: CGFloat, @ViewBuilder _ content: () -> some View) -> some View {
    VStack(spacing: 8, content: content)
      .animation(.spring(response: 0.4), value: center.items)
      .padding(.horizontal, 20)
      .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onFrameChange($0) }
      .padding(.top, top)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .transition(.identity)
  }

  @ViewBuilder
  private func capsules(_ items: [ToastItem]) -> some View {
    ForEach(items) { item in
      ToastRowView(toast: item) { dismiss(item.id) }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
  }

  private func dismiss(_ id: ToastItem.ID) {
    withAnimation(.spring(response: 0.4)) {
      center.dismiss(id)
    }
  }
}

#if DEBUG

// MARK: - Preview

private struct ToastPreview: View {
  @StateObject private var center = ToastCenter()

  private let samples: [(label: String, item: ToastItem)] = [
    ("Success", .success(.codeCopied)),
    ("Error", .error(.startPrivateFailed)),
    ("Warning", .warning(.connectionLost)),
    ("Info", .info(.roomJoined("General"))),
  ]

  var body: some View {
    VStack(spacing: 16) {
      ForEach(samples, id: \.label) { sample in
        Button { center.show(sample.item) } label: { Text(verbatim: sample.label) }
          .buttonStyle(.borderedProminent)
          .tint(sample.item.style.color)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(AppColors.Background.background)
    .overlay { ToastOverlayView(center: center) }
  }
}

#Preview {
  ToastPreview()
}
#endif
