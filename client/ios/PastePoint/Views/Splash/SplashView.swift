//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct SplashView: View {
  var onFinished: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var logoScale: CGFloat = 1.0
  @State private var nodesIn = false
  @State private var edgeProgress: CGFloat = 0
  @State private var packetVisible = false
  @State private var packetIndex = 0

  /// Fixed dark-navy matching the storyboard scene background (always dark,
  /// independent of system theme).
  private static let background = Color(
    .displayP3,
    red: 0.080_850_4,
    green: 0.104_981_906_7,
    blue: 0.171_103_149_7,
  )

  private let edgeColor = AppColors.Primary.p300
  private let nodeColors = [AppColors.Brand.brand, AppColors.Primary.p300]

  private let nodeCount = 5
  private let canvas: CGFloat = 170 // square the mesh lives in
  private let radius: CGFloat = 62 // ring radius for the nodes

  var body: some View {
    ZStack {
      Self.background

      logo
      mesh
        .frame(width: canvas, height: canvas)
        .offset(y: 150)
        .opacity(nodesIn ? 1 : 0)
        .accessibilityHidden(true)
    }
    .ignoresSafeArea()
    .task { await runAnimation() }
  }

  // MARK: - Pieces

  private var logo: some View {
    Image("logo")
      .resizable()
      .scaledToFit()
      .frame(width: 250, height: 255)
      .scaleEffect(logoScale)
      .offset(y: -40)
      .accessibilityHidden(true)
  }

  private var mesh: some View {
    ZStack {
      edgePath
        .trim(from: 0, to: edgeProgress)
        .stroke(edgeColor.opacity(0.45), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))

      ForEach(0..<nodeCount, id: \.self) { index in
        Circle()
          .fill(nodeColors[index % nodeColors.count])
          .frame(width: 10, height: 10)
          .scaleEffect(nodesIn ? 1 : 0.1)
          .position(point(index))
          .animation(.spring(response: 0.4, dampingFraction: 0.6).delay(Double(index) * 0.06), value: nodesIn)
      }

      Circle()
        .fill(.white)
        .frame(width: 7, height: 7)
        .position(point(packetIndex))
        .opacity(packetVisible ? 1 : 0)
    }
  }

  private var edgePath: Path {
    Path { path in
      for start in 0..<nodeCount {
        for end in (start + 1)..<nodeCount {
          path.move(to: point(start))
          path.addLine(to: point(end))
        }
      }
    }
  }

  private func point(_ index: Int) -> CGPoint {
    let center = canvas / 2
    let angle = (2 * .pi / Double(nodeCount)) * Double(index) - .pi / 2
    return CGPoint(x: center + radius * cos(angle), y: center + radius * sin(angle))
  }

  // MARK: - Choreography

  private func runAnimation() async {
    if reduceMotion {
      guard await pause(650) else { return }
      onFinished()
      return
    }

    guard await pause(220) else { return }

    withAnimation(.easeOut(duration: 0.18)) { nodesIn = true }
    guard await pause(150) else { return }
    withAnimation(.easeInOut(duration: 0.4)) { edgeProgress = 1 }

    guard await pause(220) else { return }
    packetVisible = true
    for hop in 1...nodeCount {
      withAnimation(.easeInOut(duration: 0.15)) { packetIndex = hop % nodeCount }
      guard await pause(150) else { return }
    }

    withAnimation(.easeIn(duration: 0.38)) { logoScale = 1.12 }
    guard await pause(120) else { return }
    onFinished()
  }

  /// Sleeps for `ms` milliseconds, returning `false` if the task was cancelled
  /// (e.g. the view went away) so the caller bails instead of finishing.
  private func pause(_ ms: Int) async -> Bool {
    (try? await Task.sleep(for: .milliseconds(ms))) != nil
  }
}

#if DEBUG
#Preview {
  SplashView {}
}
#endif
