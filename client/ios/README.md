# PastePoint Client (iOS)

The SwiftUI client for iPhone and iPad.
It uses the same signaling and data-channel protocol as the web client, so iOS and web devices can share with each other.
For what PastePoint does and how to start the whole stack, see the [root readme](../../README.md).

## Requirements

- Xcode 27.0. It is pinned in `.xcode-version`, and CI builds with the same version.
- iOS 17.6 or later, on iPhone and iPad (`IPHONEOS_DEPLOYMENT_TARGET` in the Xcode project).
- A PastePoint server. Run it with Docker Compose (see the [root readme](../../README.md)) or with `cargo run` (see the [server readme](../../server/README.md)).

### Swift packages

Xcode resolves these when you open the project.
Their versions are pinned in `PastePoint.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

| Package                                                   | Used for                                    |
| --------------------------------------------------------- | ------------------------------------------- |
| [WebRTC](https://github.com/stasel/WebRTC)                | Peer connections and data channels          |
| [BlakeHash](https://github.com/trancee/blake-hash)        | BLAKE3 file hashes                          |
| [swift-log](https://github.com/apple/swift-log)           | The API behind the global `log`             |
| [sentry-cocoa](https://github.com/getsentry/sentry-cocoa) | Error and performance reports, Release only |

The Settings app lists the packages' licenses from `PastePoint/Resources/Settings.bundle/Acknowledgements.plist`.
`scripts/acknowledgements/generate_ios_acknowledgements.py` generates that file.
Regenerate it when you add, update or remove a package (see [CONTRIBUTING.md](../../CONTRIBUTING.md)). CI fails when it is out of date.

## Run the app

### Point the app at a server

Set the two `DEBUG` constants, `host` and `wsPort`, in `PastePoint/Core/Config/AppEnvironment.swift`.

| Server                   | `wsPort`                                                                |
| ------------------------ | ----------------------------------------------------------------------- |
| Docker Compose           | `nil`: the app uses port 443, and the server's port 9000 stays internal |
| `cargo run` in `server/` | `9000`                                                                  |

- Set `host` to the Mac running the server. The simulator reaches it at `127.0.0.1`, the committed default.
- A device needs the Mac's LAN IP. `scripts/configure-network.sh` asks for it and writes it into `host` and the web and server development configs. It does not change `wsPort`.
- Debug builds trust any server certificate (`InsecureSession`), so the development server's self-signed certificate works. Release builds connect to `pastepoint.com` with normal certificate checks.
- Keep these edits local. Don't commit them.

### Simulator

Open `PastePoint.xcodeproj`, choose the `PastePoint` scheme and a simulator, and press ⌘R.
Chat and transfers need a second peer: another simulator, a device, or the web client.

### Device

1. Select the `PastePoint` target and open **Signing & Capabilities**.
2. Choose your own **Team**.
3. Change the bundle identifier from `com.pastepoint.ios` to one your team can use.
4. On a free Personal Team, remove the **Associated Domains** capability (`applinks:pastepoint.com` in `PastePoint/Resources/PastePoint.entitlements`). Personal Teams can't sign it.
5. Don't commit any of these changes.

- Allow Local Network access when the app asks on first launch. Without it, the app can't reach a server on your LAN.
- Universal links open only builds signed as `KH5NHCFH44.com.pastepoint.ios`, the app ID in `client/web/public/.well-known/apple-app-site-association`.

## Before you push

Run the checks listed in [CONTRIBUTING.md](../../CONTRIBUTING.md).
CI (`.github/workflows/ios.yml`) runs the lint, Periphery and acknowledgements checks and builds Debug and Release. It runs no tests.

## Conventions

### Concurrency

- The app target uses Swift 6 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES`.
- So types and functions in the app default to the main actor. Mark code `nonisolated` to opt out.
- WebRTC calls its delegate methods off the main thread. Mark them `nonisolated`, copy out the values you need, then hop back with `Task { @MainActor in ... }`. `SignalingService` shows the pattern.
- To carry a non-`Sendable` WebRTC object across that hop, wrap it in `UnsafeSendable` (`Core/Utils/Concurrency/`).

### Logging and Sentry

Log with the global `log` from `Core/Utils/Logging/AppLog.swift`. It needs no import, and the log category is the calling file's name.

```swift
log.debug("Offer sent to \(peer)")
log.warning("Upload failed: \(error.codeDescription)")
```

- Debug builds write all four levels to the unified log, subsystem `com.pastepoint`.
- Release builds write nothing locally and drop `debug`. They send `info` to Sentry as a breadcrumb, `warning` as a log, and `error` as an issue.
- So anything at `info` or above can leave the device. Keep usernames, chat text, filenames, room names, session codes, SDP and ICE payloads, and IP addresses at `debug`.
- Log an error with `error.codeDescription` (domain and code). Its `localizedDescription` can contain a filename.
- Sentry starts only in Release builds (`AppEnvironment.sentryEnabled`). Only `Core/Services/Monitoring/` imports `Sentry`; other code uses the global `telemetry`.

To stream debug messages from the booted simulator:

```bash
xcrun simctl spawn booted log stream --level debug --predicate 'subsystem == "com.pastepoint"'
```

### Localized strings

- `PastePoint/Resources/Localization/Localizable.xcstrings` holds the UI strings. `InfoPlist.xcstrings` holds the permission prompts.
- Every key has `en` (the source), `ar`, `es`, `fr`, `ru` and `zh-Hans`.
- Keys are symbolic, in `UPPER_SNAKE_CASE`. If the web client already has the string, reuse its key from `client/web/src/app/core/i18n/localizations/en.json`.

To add a string:

1. Add the key in Xcode's String Catalog editor, with a comment and all six translations.
2. For a plural, fill in each language's forms. `ROOMS_COUNT` has six in Arabic, four in Russian, two in English, Spanish and French, and one in Chinese.
3. Build. Xcode generates a symbol for each key (`STRING_CATALOG_GENERATE_SYMBOLS`): `SETTINGS` becomes `.settings`, and `ROOMS_COUNT` becomes `.roomsCount(_:)`.
4. Use the symbol. Use `String(localized:)` where an API takes a `String`.

```swift
Text(.settings)
Text(.roomsCount(services.roomService.rooms.count))
Label(String(localized: .blockUser), systemImage: "hand.raised")
```

## Troubleshooting

- **The app can't reach your local server.** Check `host` and `wsPort` against [Point the app at a server](#point-the-app-at-a-server). On a device, use the Mac's LAN IP and allow Local Network access in Settings > Privacy & Security > Local Network.
- **A fresh install stays offline.** The app connects only after you accept the terms screen (**Agree & Continue**). The answer is stored in `UserDefaults` under `legal.acceptedVersion`. Delete the app to see the screen again.
- **A full-screen update prompt blocks the app, and it won't connect.** The app's `MARKETING_VERSION` is below `minimum` in the server's `[client_version.ios]` policy. `cargo run` reads `server/config/development.toml`. Docker Compose reads `server/config/docker-dev.toml` (`SERVER_ENV` in `.env.development`) and bakes it into the image, so run `make dev` again after editing it. The `GET /version` response is cached for five minutes (`Cache-Control: max-age=300`), even across app launches, so wait or delete the app. A `minimum` above `latest` is ignored.
- **Xcode reports "no member" for a new string symbol.** Build once (⌘B). The symbols are generated at build time.
- **A peer that dropped off the network still appears.** The server keeps the dead connection until its heartbeat times out, about 20 seconds (`server/src/consts.rs`).
- **Lint passes locally but fails in CI.** Match your SwiftLint, SwiftFormat and Periphery versions to the pins in `.github/workflows/ios.yml`.

## Related docs

- [Root readme](../../README.md): what PastePoint is, and the Docker Compose quick start
- [CONTRIBUTING.md](../../CONTRIBUTING.md): workflow, commit messages, and the checks to run before you push
- [Server readme](../../server/README.md): running the server with `cargo run`
- [Web client readme](../web/README.md)

## License

GPL-3.0. See [LICENSE](../../LICENSE).
