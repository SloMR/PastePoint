# PastePoint Client (iOS)

The PastePoint iOS client is a native SwiftUI application for peer-to-peer file sharing and real-time chat over local networks. Features WebRTC mesh connections, chunked file transfer with integrity verification, QR-based private sessions, and full localization.

[![Swift](https://img.shields.io/badge/Swift-6.0-orange)](https://swift.org/)
[![iOS](https://img.shields.io/badge/iOS-17.6%2B-black)](https://developer.apple.com/ios/)
[![Xcode](https://img.shields.io/badge/Xcode-26.6-blue)](https://developer.apple.com/xcode/)
[![WebRTC](https://img.shields.io/badge/WebRTC-147.0-green)](https://github.com/stasel/WebRTC)

## Tech Stack

### Core Features

- **UI**: SwiftUI with a `NavigationStack` toolbar chat shell, iPad docked settings panel, and Liquid Glass toolbar items on iOS 26
- **WebRTC**: [`stasel/WebRTC`](https://github.com/stasel/WebRTC) binary distribution for peer-to-peer data channels
- **Concurrency**: Swift 6 strict concurrency — services are `@MainActor`, WebRTC delegates are `nonisolated`
- **Transport**: `URLSessionWebSocketTask` for signaling, WebRTC data channels for chat and file payloads
- **File Integrity**: BLAKE3-256 whole-file hashing (via the [`BlakeHash`](https://github.com/trancee/blake-hash) package) plus per-chunk CRC32, byte-identical to the web chunk protocol
- **Previews**: ImageIO/PDFKit thumbnail generation for file offers (`PreviewGenerator`)
- **QR Sharing**: AVFoundation camera scanning, Core Image generation for private-session invites
- **Universal Links**: `applinks:pastepoint.com` — invite URLs open the app when installed
- **I18n**: String Catalogs (English, Arabic (RTL), Spanish, French, Russian, Simplified Chinese)
- **Logging**: [`swift-log`](https://github.com/apple/swift-log) bridged to `os.Logger` under subsystem `com.pastepoint`

### Development Tools

- **Build Tool**: Xcode 26.6 (pinned in `.xcode-version`), synchronized folder groups
- **Dependencies**: Swift Package Manager (pinned in `Package.resolved`)
- **Testing**: XCTest via the `PastePointTests.xctestplan` test plan
- **Linting**: SwiftLint 0.65.0 (`.swiftlint.yml`, `--strict` in CI)
- **Formatting**: SwiftFormat 0.61.1 (`.swiftformat`, Swift 6 language mode)

## Project Structure

```
ios/
├── PastePoint/
│   ├── App/                        # App entry point and root composition
│   ├── Core/
│   │   ├── Config/                 # Environment and networking config
│   │   ├── Legal/                  # Consent storage
│   │   ├── Models/                 # Chat, signaling, and transfer models
│   │   ├── Permissions/            # Camera and Local Network helpers
│   │   ├── Services/               # App, transport, room, and transfer logic
│   │   └── Utils/                  # Logging, colors, avatars, and toasts
│   ├── Views/
│   │   ├── Chat/                   # Chat screen and components
│   │   ├── Settings/               # Settings sections and sheets
│   │   ├── Components/             # Shared UI components
│   │   ├── Attachment/             # File, photo, and camera pickers
│   │   ├── Welcome/                # Onboarding
│   │   ├── Splash/                 # Animated launch handoff
│   │   ├── Legal/                  # EULA gate
│   │   ├── Moderation/             # Reporting UI
│   │   └── Update/                 # Version gate
│   └── Resources/
│       ├── Assets.xcassets         # Colors, icons, avatars, and app icon
│       ├── Fonts/                  # Expo Arabic family
│       ├── Localization/           # String Catalogs
│       ├── Info.plist              # Permissions and app metadata
│       └── PastePoint.entitlements # Associated domains
├── PastePointTests/                # Unit tests
├── PastePointUITests/              # UI tests
├── PastePoint.xcodeproj            # Xcode project
├── .swiftlint.yml                  # SwiftLint configuration
├── .swiftformat                    # SwiftFormat configuration
├── .xcode-version                  # Pinned Xcode version
└── README.md
```

> **Note:** The project uses Xcode **synchronized groups** — the folder structure *is* the group structure. Moving files with `git mv` is safe and requires no `.pbxproj` edits.

## Quick Start

### Prerequisites

- **macOS**: Tahoe 26.2 or later
- **Xcode**: 26.6 (specified in `.xcode-version`)
- **iOS Deployment Target**: 17.6+ (iPhone and iPad)
- **Backend**: A running PastePoint server (see the [server readme](../../server/README.md) or `make dev` at the repository root)

### Development Setup

1. **Open the project**:

   ```bash
   open client/ios/PastePoint.xcodeproj
   ```

2. **Resolve dependencies**:

   Xcode resolves Swift packages automatically on first open. To do it from the command line:

   ```bash
   cd client/ios
   xcodebuild -resolvePackageDependencies -project PastePoint.xcodeproj -scheme PastePoint
   ```

3. **Point the app at your server**:

   Edit the `DEBUG` host in `PastePoint/Core/Config/AppEnvironment.swift` (see [Configuration](#configuration)).

4. **Build and run** with ⌘R against a simulator or a connected device.

### Command Line

```bash
cd client/ios

# Build for the simulator
xcodebuild build \
  -project PastePoint.xcodeproj \
  -scheme PastePoint \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Run tests
xcodebuild test \
  -project PastePoint.xcodeproj \
  -scheme PastePoint \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Lint and format
swiftlint lint --strict
swiftformat --lint .
```

## Configuration

### AppEnvironment

All hosts and endpoints live in `PastePoint/Core/Config/AppEnvironment.swift`, split by build configuration:

```swift
#if DEBUG
  private static let host = "127.0.0.1"
  private static let wsPort: Int? = 9000
#else
  private static let host = "pastepoint.com"
  private static let wsPort: Int? = nil
#endif
```

It derives the app's endpoints and local-network probe settings from those two values:

| Property                | Purpose                                      |
| ----------------------- | -------------------------------------------- |
| `webSocketUrl(_:)`      | Signaling WebSocket (`wss://…/ws[/code]`)    |
| `createSessionUrl`      | Private session creation                     |
| `versionUrl`            | Launch-time update policy check              |
| `turnCredentialsUrl`    | Short-lived TURN relay credentials           |
| `privateSessionUrl(_:)` | QR/invite universal link                     |
| `legalUrl`              | Privacy and terms pages                      |
| `localNetworkProbeHost` | Local Network permission probe host          |
| `localNetworkProbePort` | Local Network permission probe port          |
| `supportEmail`          | Destination for content reports              |

> **Note:** `wsPort` selects how the server is reached in development. Use `9000` for a standalone `cargo run` server, and `nil` when running the Docker stack, where only nginx is published on 443. Host and port changes are local-only — do not commit them.

To test against a server on your LAN, replace the `DEBUG` host with your machine's IP. `scripts/configure-network.sh` at the repository root can update it automatically.

### Entitlements and Permissions

- `PastePoint.entitlements`: `applinks:pastepoint.com` for universal links
- `NSLocalNetworkUsageDescription` + `NSBonjourServices` (`_pastepoint._tcp`): prompted once on first launch
- `NSCameraUsageDescription`: QR scanning and photo/video capture
- `NSMicrophoneUsageDescription`: recording audio with captured video
- `NSPhotoLibraryAddUsageDescription`: saving received media

Dev builds point at a LAN IP, so universal links only resolve against the production domain.

## Testing

Tests run through the `PastePointTests.xctestplan` test plan (unit tests enabled, UI tests disabled by default).

```bash
# All tests
xcodebuild test -project PastePoint.xcodeproj -scheme PastePoint \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Single test
xcodebuild test -project PastePoint.xcodeproj -scheme PastePoint \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PastePointTests/PastePointTests/testExample
```

### Two-device testing

Peer-to-peer flows need two peers. Run two simulators or a simulator plus a device against the same server.

### Linting and Formatting

```bash
swiftlint lint --strict     # CI runs this
swiftlint --fix             # Autocorrect
swiftformat .               # Format in place
swiftformat --lint .        # Check only (CI)
```

CI pins both tools (see `.github/workflows/ios.yml`); keep local versions in lockstep with `SWIFTLINT_VERSION` and `SWIFTFORMAT_VERSION`.

## Architecture

Mesh topology — one `RTCPeerConnection` per remote peer, no SFU. The signaling server relays messages without inspecting SDP or ICE content.

```
UI (SwiftUI Views)
  ↓
Orchestration  ← SignalingService
  ↓
Signaling      ← SDP/ICE exchange, glare resolution, reconnect
Data Channels  ← RTCDataChannelDelegate
  ↓
Transport      ← WebSocketConnectionService
Room State     ← RoomService + PeerDirectory
```

Key protocol invariants:

- **Role decision**: the lexicographically smaller username is the caller (plain `<` byte comparison)
- **Sequence counters**: per-peer, monotonic, with separate inbound and outbound maps
- **Data channel**: label `"data"`, `ordered: true`
- **Back-pressure**: gates binary chunks only, never control messages
- **Ephemeral identity**: the server assigns a fresh random username on every connection — there is no persisted client identity

Any change touching `SignalingService`, `BinaryChunk`, `DataChannelMessage`, or `WebRTCConfig` must preserve wire compatibility with existing peers.

## Internationalization (i18n)

### Supported Languages

- English (default)
- Arabic (RTL)
- Spanish
- French
- Russian
- Simplified Chinese

### String Catalogs

```
PastePoint/Resources/Localization/
├── Localizable.xcstrings    # UI strings
└── InfoPlist.xcstrings      # Permission usage descriptions
```

Keys use symbolic `UPPER_SNAKE_CASE` names so Xcode can generate consistent Swift symbols.

### Usage

Entries are marked `manual`, so Xcode generates `LocalizedStringResource` symbols (`UPPER_SNAKE_CASE` → `lowerCamelCase`):

```swift
Text(.privateRoom)         // no-arg key -> static var
Text(.roomsCount(count))   // format key -> static func
String(localized: .joinRoom)  // for TextField placeholders
```

> **Note:** Generated symbols only exist after a build — SourceKit reports false "no member" errors on newly added keys until then.

## Development Guide

### Code Standards

- **Swift 6**: strict concurrency, language mode 6
- **Naming**: standalone screens end in `…View`, embedded sub-sections end in `…Section`
- **Shared components**: reuse `Views/Components/` (`.pill` buttons, `.sheetContainer`, `LabeledInputField`, `StatusBanner`) rather than re-inlining markup
- **Logging**: `os.Logger` with subsystem `com.pastepoint`; log messages stay in English
- **Commits**: `iOS:` + imperative subject, `-` bullet body explaining what and why (see the [Git history](../../CONTRIBUTING.md))

### Debug Logging

The simulator has a known bug (FB5342358) where debug-level messages do not appear in Console.app. Stream them from the terminal instead:

```bash
xcrun simctl spawn <UDID> log stream --level debug \
  --predicate 'subsystem == "com.pastepoint"'
```

## Troubleshooting

### Common Issues

1. **Cannot connect to the server**:
   - Verify the host and `wsPort` in `AppEnvironment.swift` match how the server is running (standalone `cargo run` uses `:9000`; the Docker stack publishes only nginx on 443)
   - Self-signed development certificates are accepted through `InsecureSession` in `DEBUG` builds only
   - On a device, confirm the Local Network permission prompt was accepted

2. **Peers never connect**:
   - Both clients must reach the same signaling server
   - Check for phantom members after a network drop — stale sessions are reaped by the server heartbeat within ~20s

3. **"No member" errors on localization symbols**:

   ```bash
   # Symbols are generated at build time
   xcodebuild build -project PastePoint.xcodeproj -scheme PastePoint \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
   ```

4. **Swift package resolution failures**:

   ```bash
   rm -rf ~/Library/Caches/org.swift.swiftpm
   xcodebuild -resolvePackageDependencies -project PastePoint.xcodeproj -scheme PastePoint
   ```

5. **Build succeeds locally but fails CI lint**:

   ```bash
   # Match the pinned CI versions
   swiftlint version      # expect 0.65.0
   swiftformat --version  # expect 0.61.1
   ```

## Contributing

- [Contributing](../../CONTRIBUTING.md)

## License

This project is licensed under the GPL-3.0 License. See the [LICENSE](../../LICENSE) file for details.

## Related Documentation

- [Main project readme](../../README.md)
- [Server readme](../../server/README.md)
- [Docker Compose setup](../../docker-compose.yml)
