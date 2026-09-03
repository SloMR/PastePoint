//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct SettingsRoomsSection: View {
  @Environment(\.layoutDirection) private var layoutDirection
  @EnvironmentObject private var services: AppServices
  @EnvironmentObject private var toast: ToastCenter

  var body: some View {
    VStack {
      HStack(alignment: .center, spacing: 0) {
        Image("home")
          .renderingMode(.template)
          .resizable()
          .scaledToFit()
          .frame(width: 16, height: 16)
          .padding(.trailing, 5)

        Text(.rooms)
          .font(.subheadline)
          .foregroundColor(.textPrimary)

        Spacer()

        Text(.roomsCount(services.roomService.rooms.count))
          .font(.caption2)
          .foregroundColor(.textPrimary)
      }
      .padding(.horizontal)

      ForEach(services.roomService.rooms, id: \.self) { room in
        HStack(alignment: .center, spacing: 0) {
          Button {
            Task {
              log.info("Joining room")
              await services.roomService.joinOrCreateRoom(room)
              toast.show(.info(.roomJoined(room)))
            }
          } label: {
            HStack(spacing: 5) {
              Image("inactive.comment")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .scaleEffect(x: layoutDirection == .rightToLeft ? -1 : 1, y: 1)
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
