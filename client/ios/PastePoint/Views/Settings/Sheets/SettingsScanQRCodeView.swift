//
//  Copyright © 2026 PastePoint. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-only
//

import AVFoundation
import SwiftUI
import Vision
import VisionKit

// MARK: - Scanner Representable

private struct QRCodeScannerRepresentable: UIViewControllerRepresentable {
  var onCodeScanned: (String) -> Void
  var onInvalidCodeScanned: () -> Void

  func makeUIViewController(context: Context) -> DataScannerViewController {
    let scanner = DataScannerViewController(
      recognizedDataTypes: [.barcode(symbologies: [.qr])],
      qualityLevel: .fast,
      recognizesMultipleItems: false,
      isHighFrameRateTrackingEnabled: false,
      isHighlightingEnabled: false,
    )
    scanner.delegate = context.coordinator
    try? scanner.startScanning()
    return scanner
  }

  func updateUIViewController(_: DataScannerViewController, context _: Context) {}

  static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator _: Coordinator) {
    scanner.stopScanning()
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(
      onCodeScanned: onCodeScanned,
      onInvalidCodeScanned: onInvalidCodeScanned,
    )
  }

  final class Coordinator: NSObject, DataScannerViewControllerDelegate {
    var onCodeScanned: (String) -> Void
    var onInvalidCodeScanned: () -> Void
    private var hasScanned = false
    private var lastInvalidPayload: String?

    init(
      onCodeScanned: @escaping (String) -> Void,
      onInvalidCodeScanned: @escaping () -> Void,
    ) {
      self.onCodeScanned = onCodeScanned
      self.onInvalidCodeScanned = onInvalidCodeScanned
    }

    // Parses PastePoint private-session URLs and returns the embedded code.
    static func extractSessionCode(from payload: String) -> String? {
      guard
        let sessionCode = AppEnvironment.privateSessionCode(from: payload),
        SessionService.isValidSessionCode(sessionCode)
      else {
        return nil
      }

      return sessionCode
    }

    func dataScanner(
      _: DataScannerViewController,
      didAdd addedItems: [RecognizedItem],
      allItems _: [RecognizedItem],
    ) {
      guard !hasScanned else { return }
      guard
        case .barcode(let barcode) = addedItems.first,
        let payload = barcode.payloadStringValue
      else { return }

      guard let code = Self.extractSessionCode(from: payload) else {
        guard payload != lastInvalidPayload else { return }
        lastInvalidPayload = payload
        DispatchQueue.main.async { self.onInvalidCodeScanned() }
        return
      }

      hasScanned = true
      DispatchQueue.main.async { self.onCodeScanned(code) }
    }
  }
}

// MARK: - Dimming Overlay with Cutout

private struct ScannerDimmingOverlay: View {
  let cutoutSize: CGFloat

  var body: some View {
    GeometryReader { geo in
      let hole = CGRect(
        x: (geo.size.width - cutoutSize) / 2,
        y: (geo.size.height - cutoutSize) / 2,
        width: cutoutSize,
        height: cutoutSize,
      )
      Path { path in
        path.addRect(CGRect(origin: .zero, size: geo.size))
        path.addRoundedRect(in: hole, cornerSize: CGSize(width: 16, height: 16))
      }
      .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
    }
    .ignoresSafeArea()
  }
}

// MARK: - Corner Brackets Shape

private struct ViewfinderBracketsShape: Shape {
  let bracketLength: CGFloat = 28
  let cornerRadius: CGFloat = 4

  func path(in rect: CGRect) -> Path {
    var path = Path()
    let cr = cornerRadius
    let bl = bracketLength

    // Top-left
    path.move(to: CGPoint(x: rect.minX, y: rect.minY + bl))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cr))
    path.addArc(
      center: CGPoint(x: rect.minX + cr, y: rect.minY + cr),
      radius: cr,
      startAngle: .degrees(180),
      endAngle: .degrees(270),
      clockwise: false,
    )
    path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.minY))

    // Top-right
    path.move(to: CGPoint(x: rect.maxX - bl, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - cr, y: rect.minY))
    path.addArc(
      center: CGPoint(x: rect.maxX - cr, y: rect.minY + cr),
      radius: cr,
      startAngle: .degrees(270),
      endAngle: .degrees(0),
      clockwise: false,
    )
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + bl))

    // Bottom-right
    path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - bl))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cr))
    path.addArc(
      center: CGPoint(x: rect.maxX - cr, y: rect.maxY - cr),
      radius: cr,
      startAngle: .degrees(0),
      endAngle: .degrees(90),
      clockwise: false,
    )
    path.addLine(to: CGPoint(x: rect.maxX - bl, y: rect.maxY))

    // Bottom-left
    path.move(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX + cr, y: rect.maxY))
    path.addArc(
      center: CGPoint(x: rect.minX + cr, y: rect.maxY - cr),
      radius: cr,
      startAngle: .degrees(90),
      endAngle: .degrees(180),
      clockwise: false,
    )
    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - bl))

    return path
  }
}

// MARK: - Main View

struct SettingsScanQRCodeView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var toast: ToastCenter

  private let cutoutSize: CGFloat = 240
  @State private var bracketScale: CGFloat = 1.0
  @State private var cameraPermission: AVAuthorizationStatus = CameraPermission.status

  var onCodeScanned: (String) -> Void

  var body: some View {
    if DataScannerViewController.isSupported {
      switch cameraPermission {
      case .authorized:
        scannerView
      case .notDetermined:
        Color.black.ignoresSafeArea()
          .task { cameraPermission = await CameraPermission.request() }
      default:
        CameraPermissionDeniedView()
      }
    } else {
      ZStack(alignment: .topTrailing) {
        ContentUnavailableView(
          String(localized: .scannerUnavailable),
          systemImage: "camera.slash",
          description: Text(.qrScanningNotSupported),
        )
        Button { dismiss() } label: {
          ZStack {
            Circle()
              .fill(Color(.systemGray5))
              .frame(width: 36, height: 36)
            Image(systemName: "xmark")
              .font(.system(size: 13, weight: .bold, design: .rounded))
              .foregroundStyle(.secondary)
          }
          .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.close))
        .padding(.horizontal)
        .padding(.top, 56)
      }
    }
  }

  private var scannerView: some View {
    ZStack {
      // Camera feed
      QRCodeScannerRepresentable { code in
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        log.info("QR code scanned successfully")
        onCodeScanned(code)
        dismiss()
      } onInvalidCodeScanned: {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        log.warning("Invalid QR code scanned")
        toast.show(.error(.invalidQrCode))
      }
      .ignoresSafeArea()

      // Dimming overlay with clear cutout
      ScannerDimmingOverlay(cutoutSize: cutoutSize)

      // Animated corner brackets
      ViewfinderBracketsShape()
        .stroke(AppColors.Brand.brand, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        .frame(width: cutoutSize, height: cutoutSize)
        .scaleEffect(bracketScale)
        .animation(
          .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
          value: bracketScale,
        )
        .onAppear { bracketScale = 1.04 }

      // UI chrome
      VStack(spacing: 0) {
        // Close button
        HStack {
          Spacer()
          Button { dismiss() } label: {
            ZStack {
              Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 36, height: 36)
              Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            }
            .contentShape(Circle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text(.close))
        }
        .padding(.horizontal, 24)
        .padding(.top, 56)
        .padding(.bottom, 24)

        Spacer()

        // Bottom instruction card
        HStack(spacing: 12) {
          Image(systemName: "qrcode.viewfinder")
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(AppColors.Brand.brand)
          Text(.pointCameraAtQr)
            .font(.subheadline)
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 32)
        .padding(.bottom, 56)
        .background(
          LinearGradient(
            colors: [.clear, .black.opacity(0.5)],
            startPoint: .top,
            endPoint: .bottom,
          ),
        )
      }
    }
    .ignoresSafeArea()
  }
}

// MARK: - Preview

#if DEBUG
#Preview {
  SettingsScanQRCodeView { code in
    print("Scanned: \(code)")
  }
  .environmentObject(ToastCenter())
}
#endif
