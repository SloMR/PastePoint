//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Logging
import SwiftUI

struct SettingsRoomsSection: View {
  @EnvironmentObject private var services: AppServices
  @Binding var toasts: [ToastItem]

  private let logger = Logger(label: "SettingsRoomsSection")

  var body: some View {
    VStack {
      HStack(alignment: .center, spacing: 0) {
        Image("home")
          .renderingMode(.template)
          .resizable()
          .scaledToFit()
          .frame(width: 16, height: 16)
          .padding(.trailing, 5)

        Text("Chat Rooms")
          .font(.subheadline)
          .foregroundColor(.textPrimary)

        Spacer()

        Text("\(services.roomService.rooms.count) Rooms")
          .font(.caption2)
          .foregroundColor(.textPrimary)
      }
      .padding(.horizontal)

      ForEach(services.roomService.rooms, id: \.self) { room in
        HStack(alignment: .center, spacing: 0) {
          Button {
            Task {
              logger.info("Joining room \(room)")
              await services.roomService.joinOrCreateRoom(room)
              toasts.append(.info("Joined \(room)"))
            }
          } label: {
            HStack(spacing: 5) {
              Image("inactive.comment")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(room == services.roomService.currentRoom ? .brand : .secondary)

              Text(room)
                .font(.subheadline)
                .foregroundColor(room == services.roomService.currentRoom ? .brand : .textPrimary)
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)

          Spacer()
        }
        .padding(.horizontal, 60)
        .padding(.bottom, 2)
      }
    }
  }
}
