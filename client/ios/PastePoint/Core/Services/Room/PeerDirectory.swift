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

  init(roomService: RoomService, userService: UserService, blockService: BlockService) {
    roomService.$members
      .combineLatest(userService.$user, blockService.$blockedPeers)
      .map { members, user, blocked in
        members.filter { $0 != user && !user.isEmpty && !blocked.contains($0) }.sorted()
      }
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .assign(to: &$peers)
  }
}
