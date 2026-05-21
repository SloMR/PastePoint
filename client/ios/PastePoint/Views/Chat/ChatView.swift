//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct ChatView: View {
  @EnvironmentObject private var services: AppServices
  @State private var scrolledID: ChatMessage.ID?

  let messages: [ChatMessage]

  private var isPrivate: Bool {
    services.wsService.currentSessionCode != nil
  }

  var body: some View {
    GeometryReader { geometry in
      ScrollViewReader { proxy in
        ScrollView {
          // TODO: Change VStack to be LazyVStack
          VStack(alignment: .leading, spacing: 16) {
            ChatRoomHeader(isPrivate: isPrivate)

            Spacer(minLength: 0)

            ForEach(messages) { message in
              ChatMessageBubble(
                alignment: alignment(for: message),
                name: message.from,
                time: timeString(message.timestamp),
                text: message.text,
              )
              .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .opacity,
              ))
            }
          }
          .scrollTargetLayout()
          .frame(maxWidth: .infinity, minHeight: geometry.size.height - 16, alignment: .leading)
          .padding(.horizontal, 16)
          .padding(.bottom, 16)
          .contentShape(Rectangle())
          .onTapGesture { dismissKeyboard() }
          .animation(.spring(duration: 0.3, bounce: 0.2), value: messages.count)
        }
        .scrollDismissesKeyboard(.interactively)
        .defaultScrollAnchor(.bottom)
        .scrollPosition(id: $scrolledID, anchor: .bottom)
        .onChange(of: messages.last?.id) { oldLastID, newLastID in
          guard scrolledID == oldLastID, let newLastID else { return }
          withAnimation(.spring(duration: 0.3, bounce: 0.1)) {
            scrolledID = newLastID
          }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notif in
          preserveAnchor(notif: notif, proxy: proxy)
        }
      }
    }
  }

  private func dismissKeyboard() {
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder),
      to: nil,
      from: nil,
      for: nil,
    )
  }

  // TODO: Replace this SwiftUI scrollTo workaround with a UIKit-backed chat list
  // so keyboard open/close can sync contentInset and contentOffset in one animation.
  private func preserveAnchor(notif: Notification, proxy: ScrollViewProxy) {
    guard
      let id = scrolledID,
      let userInfo = notif.userInfo,
      let systemDuration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
      let curve = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
    else { return }

    withAnimation(keyboardAnimation(curve: curve, duration: systemDuration)) {
      proxy.scrollTo(id, anchor: .bottom)
    }
  }

  private func keyboardAnimation(curve: UInt, duration: Double) -> Animation {
    switch UIView.AnimationCurve(rawValue: Int(curve)) {
    case .easeInOut:
      return .easeInOut(duration: duration)
    case .easeIn:
      return .easeIn(duration: duration)
    case .easeOut:
      return .easeOut(duration: duration)
    case .linear:
      return .linear(duration: duration)
    default:
      return .easeOut(duration: duration)
    }
  }

  private func alignment(for message: ChatMessage) -> MessageAlignment {
    message.from == services.userService.user ? .trailing : .leading
  }

  private func timeString(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
  }
}

// MARK: - Preview

#if DEBUG
#Preview {
  let services = AppServices.preview
  services.userService.user = "Gwen Kuphal"

  return ChatView(messages: [
    ChatMessage(
      from: "Garry Schulist",
      text: "Hello",
      timestamp: dateAt(hour: 21, minute: 4),
    ),
    ChatMessage(
      from: "Gwen Kuphal",
      text: "Hi",
      timestamp: dateAt(hour: 21, minute: 5),
    ),
  ])
  .environmentObject(services)
}

private func dateAt(hour: Int, minute: Int) -> Date {
  Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
}
#endif
