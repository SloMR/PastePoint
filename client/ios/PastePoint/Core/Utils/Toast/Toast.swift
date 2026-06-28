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
  let id = UUID()
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
    .onTapGesture { onDismiss() }
    .task {
      try? await Task.sleep(for: .seconds(2))
      onDismiss()
    }
  }
}

// MARK: - Toast Overlay

/// Renders the active toasts at the top edge of its container. Hosted in the
/// global overlay window (see `ToastWindow`) bound to the shared `ToastCenter`,
/// so toasts float above every view — including sheets.
struct ToastOverlayView: View {
  @ObservedObject var center: ToastCenter

  var body: some View {
    VStack(spacing: 8) {
      ForEach(center.items) { item in
        ToastRowView(toast: item) {
          withAnimation(.spring(response: 0.4)) {
            center.dismiss(item.id)
          }
        }
        .transition(.asymmetric(
          insertion: .move(edge: .top).combined(with: .opacity),
          removal: .move(edge: .top).combined(with: .opacity),
        ))
      }

      Spacer(minLength: 0)
    }
    .padding(.horizontal, 20)
    .padding(.top, 8)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .animation(.spring(response: 0.4), value: center.items)
  }
}

#if DEBUG

// MARK: - Preview

private struct ToastPreview: View {
  @StateObject private var center = ToastCenter()

  var body: some View {
    VStack(spacing: 16) {
      Spacer()

      Button { center.show(.success(.codeCopied)) } label: { Text(verbatim: "Success") }
        .buttonStyle(.borderedProminent)
        .tint(AppColors.Status.success)

      Button { center.show(.error(.startPrivateFailed)) } label: { Text(verbatim: "Error") }
        .buttonStyle(.borderedProminent)
        .tint(AppColors.Status.danger)

      Button { center.show(.warning(.connectionLost)) } label: { Text(verbatim: "Warning") }
        .buttonStyle(.borderedProminent)
        .tint(AppColors.Status.warning)

      Button { center.show(.info(.roomJoined("General"))) } label: { Text(verbatim: "Info") }
        .buttonStyle(.borderedProminent)
        .tint(AppColors.Status.info)

      Spacer()
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
