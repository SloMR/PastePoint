//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

// MARK: - Close Button

struct CloseButton: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    if #available(iOS 26, *) {
      Button(role: .close) { dismiss() }
    } else {
      Button { dismiss() } label: {
        ZStack {
          Circle()
            .fill(Color(UIColor.tertiarySystemFill))
            .frame(width: 36, height: 36)
          Image(systemName: "xmark")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(Color(UIColor.secondaryLabel))
        }
        .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(.close))
    }
  }
}

// MARK: - Sheet Container

private struct SheetContainer: ViewModifier {
  let title: LocalizedStringResource?
  let extraHeight: CGFloat

  @State private var height: CGFloat

  init(title: LocalizedStringResource?, initialHeight: CGFloat, extraHeight: CGFloat) {
    self.title = title
    self.extraHeight = extraHeight
    _height = State(initialValue: initialHeight)
  }

  func body(content: Content) -> some View {
    formFitted(
      NavigationStack {
        content
          .frame(maxWidth: .infinity)
          .fixedSize(horizontal: false, vertical: true)
          .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured in
            guard measured > 0 else { return }
            height = measured + extraHeight
          }
          .navigationTitle(title.map { Text($0) } ?? Text(verbatim: ""))
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .topBarTrailing) { CloseButton() }
          }
      }
      .presentationDetents([.height(height)])
      .presentationDragIndicator(.visible)
      .presentationBackground(AppColors.Background.background),
    )
  }

  /// iPad: form-sheet width with content-fitted height (height detents only apply in compact).
  /// `idealHeight` feeds the fitted sizing the measured height, which already
  /// includes the nav-bar allowance the stack's own ideal size leaves out.
  @ViewBuilder
  private func formFitted(_ sheet: some View) -> some View {
    if #available(iOS 18, *) {
      sheet
        .frame(idealHeight: height)
        .presentationSizing(.form.fitted(horizontal: false, vertical: true))
    } else {
      sheet
    }
  }
}

extension View {
  func sheetContainer(
    title: LocalizedStringResource? = nil,
    initialHeight: CGFloat = 320,
    extraHeight: CGFloat = 56,
  ) -> some View {
    modifier(SheetContainer(title: title, initialHeight: initialHeight, extraHeight: extraHeight))
  }
}
