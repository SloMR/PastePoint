//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Logging
import SwiftUI

struct SettingsPrivateSessionSection: View {
  @EnvironmentObject private var services: AppServices
  @EnvironmentObject private var toast: ToastCenter

  @State private var isQRCodeSheetPresented: Bool = false
  @State private var isJoinPrivateSessionPresented: Bool = false
  @State private var isStarting: Bool = false

  private let logger = Logger(label: "SettingsPrivateSessionSection")
  var onSessionJoin: (() -> Void)?

  var body: some View {
    Group {
      if let code = services.wsService.currentSessionCode {
        activeSessionView(code: code)
      } else {
        joinOrStartView
      }
    }
    .sheet(isPresented: $isQRCodeSheetPresented) {
      SettingsQRCodeView()
    }
    .sheet(isPresented: $isJoinPrivateSessionPresented) {
      SettingsJoinPrivateView(onSessionJoin: onSessionJoin)
    }
  }

  private func activeSessionView(code: String) -> some View {
    VStack(alignment: .leading) {
      HStack(alignment: .center, spacing: 0) {
        Image("code")
          .renderingMode(.template)
          .resizable()
          .scaledToFit()
          .frame(width: 16, height: 16)
          .padding(.trailing, 5)

        Text(.code)
          .font(.subheadline)
          .foregroundColor(.textPrimary)
      }

      ZStack(alignment: .center) {
        RoundedRectangle(cornerRadius: 10)
          .fill(.inputBackground)
          .padding(.horizontal)

        Text(code)
          .font(.system(size: 18, weight: .medium, design: .monospaced))
          .foregroundColor(.textPrimary)
          .padding(.vertical, 14)
      }

      HStack(alignment: .center, spacing: 16) {
        Spacer()

        // Copy Button
        Button {
          UIPasteboard.general.string = code
          toast.show(.success(.codeCopied))
        } label: {
          Image("copy")
            .font(.system(size: 18, weight: .medium))
            .foregroundColor(.white)
            .frame(width: 50, height: 50)
            .background(
              RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.Brand.brand),
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.copy))

        // QR Button
        Button {
          // Show QR sheet
          isQRCodeSheetPresented = true
        } label: {
          Image("qrcode")
            .font(.system(size: 18, weight: .medium))
            .foregroundColor(.white)
            .frame(width: 50, height: 50)
            .background(
              RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.Brand.brand),
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.qrCode))

        Spacer()
      }
    }
    .padding(.top, 22)
    .padding(.horizontal)
  }

  private var joinOrStartView: some View {
    VStack(spacing: 8) {
      Button {
        Task {
          isStarting = true
          do {
            logger.info("Start private session button tapped")
            let code = try await services.sessionService.getNewSessionCode()
            await services.wsService.setupPrivateSession(code)
            isStarting = false
            guard await services.connectIfPermitted() else {
              toast.show(.error(.localNetworkOffStart))
              return
            }
            toast.show(.success(.privateSessionStarted))
            await services.roomService.listRooms()
            await services.userService.getUsername()
          } catch {
            isStarting = false
            logger.error("Cannot get the session code \(error)")
            toast.show(.error(.startPrivateFailed))
          }
        }
      } label: {
        HStack(spacing: 8) {
          if isStarting {
            ProgressView()
              .progressViewStyle(.circular)
              .tint(.brand)
              .scaleEffect(0.85)
          } else {
            Image("plus")
              .renderingMode(.template)
              .resizable()
              .scaledToFit()
              .frame(width: 24, height: 24)
          }
          Text(isStarting ? .starting : .createPrivateSession)
            .font(.headline)
        }
        .foregroundStyle(.brand)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
          RoundedRectangle(cornerRadius: 8)
            .stroke(.brand, lineWidth: 0.8),
        )
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(isStarting)

      Button {
        logger.info("Join private session button tapped")
        isJoinPrivateSessionPresented = true
      } label: {
        HStack(spacing: 8) {
          Text(.joinPrivateSession)
            .font(.headline)
        }
        .foregroundStyle(.brand)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
          RoundedRectangle(cornerRadius: 8)
            .stroke(.brand, lineWidth: 0.8),
        )
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(isStarting)
    }
    .padding(.horizontal)
    .padding(.top, 22)
    .padding(.bottom, 44)
  }
}
