//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct LabeledInputField<Trailing: View>: View {
  @ViewBuilder var trailing: () -> Trailing
  @Binding var text: String

  let label: LocalizedStringResource?
  let placeholder: LocalizedStringResource
  let description: LocalizedStringResource?

  init(
    label: LocalizedStringResource? = nil,
    placeholder: LocalizedStringResource,
    text: Binding<String>,
    description: LocalizedStringResource? = nil,
    @ViewBuilder trailing: @escaping () -> Trailing,
  ) {
    self.label = label
    self.placeholder = placeholder
    _text = text
    self.description = description
    self.trailing = trailing
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let label {
        Text(label)
          .font(.subheadline)
          .foregroundStyle(.textPrimary)
      }

      HStack(spacing: 0) {
        TextField(String(localized: placeholder), text: $text)
          .textFieldStyle(.plain)
          .font(.body)
          .foregroundStyle(.textPrimary)
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
          .padding(.leading, 14)
          .padding(.vertical, 12)

        if !text.isEmpty {
          Button { text = "" } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 16))
              .foregroundStyle(.textSecondary)
              .frame(width: 36, height: 44)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text(.clear))
        }

        trailing()
      }
      .background(AppColors.Background.input, in: RoundedRectangle(cornerRadius: 8))

      if let description {
        Text(description)
          .font(.caption)
          .foregroundStyle(.textSecondary)
      }
    }
  }
}

extension LabeledInputField where Trailing == EmptyView {
  init(
    label: LocalizedStringResource? = nil,
    placeholder: LocalizedStringResource,
    text: Binding<String>,
    description: LocalizedStringResource? = nil,
  ) {
    self.init(label: label, placeholder: placeholder, text: text, description: description) { EmptyView() }
  }
}
