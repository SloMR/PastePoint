//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Logging
import SwiftUI

struct SettingsCreateRoomView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var services: AppServices

  private let logger = Logger(label: "SettingsCreateRoomView")

  var onRoomCreate: (() -> Void)?

  @State private var roomName: String = ""

  private var sanitizedRoomName: String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
    let filtered = String(String.UnicodeScalarView(roomName.unicodeScalars.filter { allowed.contains($0) }))
    return String(filtered.trimmingCharacters(in: .whitespaces).prefix(64))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {

      // Input
      VStack(alignment: .leading, spacing: 6) {
        Text(.enterRoomName)
          .font(.subheadline)
          .foregroundStyle(.textPrimary)

        HStack(spacing: 0) {
          TextField(String(localized: .roomNamePlaceholder), text: $roomName)
            .textFieldStyle(.plain)
            .font(.body)
            .foregroundStyle(.textPrimary)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(.leading, 14)
            .padding(.vertical, 12)

          if !roomName.isEmpty {
            Button { roomName = "" } label: {
              Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.textSecondary)
                .frame(width: 36, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(.clear))
            .padding(.trailing, 8)
          }
        }
        .background(AppColors.Background.input, in: RoundedRectangle(cornerRadius: 8))

        Text(.roomNameDescription)
          .font(.caption)
          .foregroundStyle(.textSecondary)
      }

      // Buttons
      HStack(spacing: 12) {
        Button {
          logger.info("User joining room with name: \(sanitizedRoomName)")
          Task {
            await services.roomService.joinOrCreateRoom(sanitizedRoomName)
            logger.info("Successfully joined room: \(sanitizedRoomName)")
            dismiss()
            onRoomCreate?()
          }
        } label: {
          Text(.done)
        }
        .buttonStyle(.pill(tint: AppColors.Brand.brand))
        .disabled(sanitizedRoomName.isEmpty)
        .opacity(sanitizedRoomName.isEmpty ? 0.6 : 1)

        Button {
          logger.info("Dismiss join private session")
          dismiss()
        } label: {
          Text(.cancel)
        }
        .buttonStyle(.pill(.outlined, tint: AppColors.Brand.brand))
      }
    }
    .padding(24)
    .sheetContainer(title: .createANewRoom)
  }
}

// MARK: - Preview

#if DEBUG
#Preview {
  SettingsCreateRoomView()
    .environmentObject(AppServices.preview)
}
#endif
