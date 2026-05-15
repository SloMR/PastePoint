//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import Combine
import Foundation

@MainActor
final class PeerDirectory: ObservableObject {
  @Published private(set) var peers: [String] = []
  private var cancellables: Set<AnyCancellable> = []

  init(roomService: RoomService, userService: UserService) {
    roomService.$members
      .combineLatest(userService.$user)
      .map { members, user in
        members.filter { $0 != user && !user.isEmpty }.sorted()
      }
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .assign(to: &$peers)
  }
}
