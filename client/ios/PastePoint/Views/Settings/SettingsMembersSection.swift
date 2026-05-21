//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct SettingsMembersSection: View {
  @EnvironmentObject private var services: AppServices

  var body: some View {
    VStack {
      HStack(alignment: .center, spacing: 0) {
        Image("users")
          .renderingMode(.template)
          .resizable()
          .scaledToFit()
          .frame(width: 16, height: 16)
          .padding(.trailing, 5)

        Text("Members")
          .font(.subheadline)
          .foregroundColor(.textPrimary)

        Spacer()

        Text("\(services.roomService.members.filter { $0 != services.userService.user }.count) Online Now")
          .font(.caption2)
          .foregroundColor(.textPrimary)
      }
      .padding(.horizontal)

      Group {
        let others = services.roomService.members.filter { $0 != services.userService.user }
        if others.isEmpty {
          Text("No one is online right now")
            .font(.subheadline)
            .foregroundColor(.textPrimary)
            .fontWeight(.bold)
        } else {
          ForEach(others, id: \.self) { member in
            let isConnected = services.signalingService.connectedPeers.contains(member)

            HStack(alignment: .center, spacing: 0) {
              Circle()
                .fill(isConnected ? Color.green : Color.red)
                .frame(width: 14, height: 14)
                .padding(.trailing, 6)

              Text(member)
                .font(.subheadline)
                .foregroundColor(.textPrimary)

              Spacer()

              Image("link")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .padding(.trailing, 5)
                .foregroundStyle(.textSecondary)
            }
            .animation(.easeInOut(duration: 0.2), value: isConnected)
          }
        }
      }
      .padding(.horizontal)
      .padding(.top, 22)
    }
    .padding(.top, 12)
  }
}
