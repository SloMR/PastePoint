//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct SettingsCreateRoomView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var services: AppServices

  var onRoomCreate: (() -> Void)?

  @State private var roomName: String = ""

  private var sanitizedRoomName: String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
    let filtered = String(String.UnicodeScalarView(roomName.unicodeScalars.filter { allowed.contains($0) }))
    return String(filtered.trimmingCharacters(in: .whitespaces).prefix(64))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {

      LabeledInputField(
        label: .enterRoomName,
        placeholder: .roomNamePlaceholder,
        text: $roomName,
        description: .roomNameDescription,
      )

      // Buttons
      HStack(spacing: 12) {
        Button {
          log.info("User joining room with name: \(sanitizedRoomName)")
          Task {
            await services.roomService.joinOrCreateRoom(sanitizedRoomName)
            log.info("Successfully joined room: \(sanitizedRoomName)")
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
          log.info("Dismiss join private session")
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
