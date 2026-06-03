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
  @State private var sheetHeight: CGFloat = 320

  private var sanitizedRoomName: String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
    let filtered = String(String.UnicodeScalarView(roomName.unicodeScalars.filter { allowed.contains($0) }))
    return String(filtered.trimmingCharacters(in: .whitespaces).prefix(64))
  }

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 16) {

        // Input
        VStack(alignment: .leading, spacing: 6) {
          Text("Enter the Room Name")
            .font(.subheadline)
            .foregroundStyle(.textPrimary)

          HStack(spacing: 0) {
            TextField("Room name", text: $roomName)
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
              .padding(.trailing, 8)
            }
          }
          .background(AppColors.Background.input, in: RoundedRectangle(cornerRadius: 8))

          Text("Enter a name for the room you want to join or create.")
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
            Text("Done")
              .fontWeight(.semibold)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 14)
              .foregroundStyle(.white)
              .background(AppColors.Brand.brand, in: Capsule())
          }
          .buttonStyle(.plain)
          .disabled(sanitizedRoomName.isEmpty)
          .opacity(sanitizedRoomName.isEmpty ? 0.6 : 1)

          Button {
            logger.info("Dismiss join private session")
            dismiss()
          } label: {
            Text("Cancel")
              .fontWeight(.semibold)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 14)
              .foregroundStyle(AppColors.Brand.brand)
              .background(Color.clear, in: Capsule())
              .overlay(Capsule().stroke(AppColors.Brand.brand, lineWidth: 1.5))
          }
          .buttonStyle(.plain)
        }
      }
      .padding(24)
      .frame(maxWidth: .infinity)
      .fixedSize(horizontal: false, vertical: true)
      .onGeometryChange(for: CGFloat.self) { proxy in
        proxy.size.height
      } action: { height in
        guard height > 0 else { return }
        sheetHeight = height + 56
      }
      .navigationTitle("Create a Room")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          if #available(iOS 26, *) {
            Button(role: .close) {
              dismiss()
            }
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
          }
        }
      }
    }
    .presentationDetents([.height(sheetHeight)])
    .presentationDragIndicator(.visible)
    .presentationBackground(AppColors.Background.background)
  }
}

// MARK: - Preview

#if DEBUG
#Preview {
  SettingsCreateRoomView()
    .environmentObject(AppServices.preview)
}
#endif
