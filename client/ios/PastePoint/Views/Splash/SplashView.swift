//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import SwiftUI

struct SplashView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var devicesIn = false
  @State private var edgeProgress: CGFloat = 0
  @State private var packetVisible = false
  @State private var packetPhase: CGFloat = 0

  /// Fixed dark-navy matching the storyboard scene background (always dark,
  /// independent of system theme).
  private static let background = Color(
    .displayP3,
    red: 0.080_850_4,
    green: 0.104_981_906_7,
    blue: 0.171_103_149_7,
  )

  private let iconColor = AppColors.Primary.p300
  private var edgeGradient: LinearGradient {
    LinearGradient(
      colors: [AppColors.Primary.p300.opacity(0.7), AppColors.Brand.brand.opacity(0.7)],
      startPoint: .leading,
      endPoint: .trailing,
    )
  }

  private let deviceFont: CGFloat = 44
  private let wireWidth: CGFloat = 84
  private let wireHeight: CGFloat = 48
  private let deviceGap: CGFloat = 16

  var body: some View {
    ZStack {
      Self.background

      logo
      link
        .offset(y: 160)
        .opacity(devicesIn ? 1 : 0)
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
      .offset(y: -40)
      .accessibilityHidden(true)
  }

  private var link: some View {
    HStack(spacing: deviceGap) {
      deviceIcon("iphone")
        .scaleEffect(devicesIn ? 1 : 0.1)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: devicesIn)

      wire

      deviceIcon("display")
        .scaleEffect(devicesIn ? 1 : 0.1)
        .animation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.08), value: devicesIn)
    }
  }

  private var wire: some View {
    ZStack {
      Path { path in
        path.move(to: CGPoint(x: 0, y: wireHeight / 2))
        path.addLine(to: CGPoint(x: wireWidth, y: wireHeight / 2))
      }
      .trim(from: 0, to: edgeProgress)
      .stroke(edgeGradient, style: StrokeStyle(lineWidth: 2, lineCap: .round))

      Circle()
        .fill(.white)
        .frame(width: 8, height: 8)
        .position(x: packetPhase * wireWidth, y: wireHeight / 2)
        .opacity(packetVisible ? 1 : 0)
    }
    .frame(width: wireWidth, height: wireHeight)
  }

  private func deviceIcon(_ name: String) -> some View {
    Image(systemName: name)
      .font(.system(size: deviceFont, weight: .regular))
      .foregroundStyle(iconColor)
  }

  // MARK: - Choreography

  private func runAnimation() async {
    if reduceMotion {
      devicesIn = true
      edgeProgress = 1
      return
    }

    guard await pause(220) else { return }
    withAnimation(.easeOut(duration: 0.18)) { devicesIn = true }
    guard await pause(180) else { return }
    withAnimation(.easeInOut(duration: 0.4)) { edgeProgress = 1 }

    guard await pause(300) else { return }
    packetVisible = true
    withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
      packetPhase = 1
    }
  }

  /// Sleeps for `ms` milliseconds, returning `false` if the task was cancelled
  /// (e.g. the view went away) so the caller bails instead of finishing.
  private func pause(_ ms: Int) async -> Bool {
    (try? await Task.sleep(for: .milliseconds(ms))) != nil
  }
}

#if DEBUG
#Preview {
  SplashView()
}
#endif
