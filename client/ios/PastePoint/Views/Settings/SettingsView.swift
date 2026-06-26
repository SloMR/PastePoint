//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Logging
import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var services: AppServices

  private let logger = Logger(label: "SettingsView")
  var onSessionJoin: (() -> Void)?

  @State private var isLeaveSessionSheetPresented: Bool = false
  @State private var isJoinRoomSheetPresented: Bool = false
  @State private var privacyURLToShow: IdentifiableURL?
  @State private var toasts: [ToastItem] = []

  private var avatar: some View {
    Image("group")
      .resizable()
      .scaledToFit()
      .frame(width: 40, height: 40)
      .padding(.trailing, 12)
  }

  var body: some View {
    VStack(spacing: 0) {

      // MARK: - Header

      HStack(alignment: .center, spacing: 0) {
        avatar

        Text(services.userService.user.isEmpty ? String(localized: .connecting) : services.userService.user)
          .font(.title3)
          .foregroundColor(services.userService.user.isEmpty ? .textSecondary : .textPrimary)

        Spacer()
      }
      .padding()

      // MARK: - Content

      ScrollView {
        VStack(spacing: 0) {

          // MARK: - Create New Room Button

          Button {
            logger.info("Create new room tapped")
            isJoinRoomSheetPresented = true
          } label: {
            HStack(spacing: 8) {
              Image("plus")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)

              Text(.createNewRoom)
                .font(.headline)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.brand),
            )
          }
          .buttonStyle(.plain)
          .padding(.horizontal)
          .padding(.top, 22)
          .padding(.bottom, 44)

          // MARK: - Chat Rooms

          SettingsRoomsSection(toasts: $toasts)

          // MARK: - Private Session

          SettingsPrivateSessionSection(toasts: $toasts, onSessionJoin: onSessionJoin)

          // MARK: - Members

          SettingsMembersSection()
        }
      }

      Spacer()

      // MARK: - Leave Private Session

      if let code = services.wsService.currentSessionCode, !code.isEmpty {
        Button {
          isLeaveSessionSheetPresented = true
        } label: {
          HStack(spacing: 8) {
            Image(systemName: "xmark")
              .font(.system(size: 14, weight: .regular))
              .frame(width: 32, height: 32)

            Text(.endSession)
              .font(.headline)
          }
          .foregroundStyle(.red)
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
      }

      // MARK: - Footer

      Divider()
        .padding()

      SettingsFooterView(privacyURLToShow: $privacyURLToShow)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(AppColors.Background.surface)
    .navigationTitle(Text(.settings))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        if #available(iOS 26, *) {
          Button(role: .close) {
            dismiss()
          }
        } else {
          Button(action: { dismiss() }, label: {
            Image(systemName: "xmark")
              .font(.body.bold())
              .foregroundStyle(.secondary)
          })
        }
      }
    }
    .sheet(isPresented: $isLeaveSessionSheetPresented) {
      SettingsLeaveSessionView {
        logger.info("User left a private session")
        toasts.append(.info(.leftPrivateSession))
      }
    }
    .sheet(isPresented: $isJoinRoomSheetPresented) {
      SettingsCreateRoomView {
        logger.info("User created a room")
        toasts.append(.success(.roomCreated))
      }
    }
    .appToast(items: $toasts)
  }
}

// MARK: - Preview

#if DEBUG
#Preview {
  SettingsView()
    .environmentObject(AppServices.preview)
}
#endif
