//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Logging
import SwiftUI

struct SettingsLeaveSession: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var services: AppServices

  private let logger = Logger(label: "SettingsLeaveSession")

  var onSessionLeft: (() -> Void)?

  @State private var sheetHeight: CGFloat = 320

  var body: some View {
    NavigationStack {
      VStack(spacing: 20) {
        Text("Are you sure you want to end the session?")
          .font(.headline)
          .multilineTextAlignment(.center)
          .foregroundStyle(.primary)
          .padding(.horizontal)

        HStack(spacing: 12) {
          Button {
            logger.info("User confirmed leaving private session")
            services.wsService.disconnect(manual: true)
            Task {
              await services.wsService.connect(sessionCode: nil)
              await services.roomService.listRooms()
              await services.userService.getUsername()
              logger.info("Successfully left private session")
              dismiss()
              onSessionLeft?()
            }
          } label: {
            Text("End Session")
              .fontWeight(.semibold)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 14)
              .foregroundStyle(.white)
              .background(Color.red, in: Capsule())
          }
          .buttonStyle(.plain)

          Button {
            logger.info("Dismiss Leave Session view")
            dismiss()
          } label: {
            Text("Cancel")
              .fontWeight(.semibold)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 14)
              .foregroundStyle(.red)
              .background(Color.clear, in: Capsule())
              .overlay(
                Capsule()
                  .stroke(Color.red, lineWidth: 1.5),
              )
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
      .navigationTitle("Leave Session")
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
  SettingsLeaveSession()
    .environmentObject(AppServices.preview)
}
#endif
