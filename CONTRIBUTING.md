# Contributing to PastePoint

Thank you for your interest in contributing to PastePoint! This guide covers the essential workflow and standards for contributing.

## Quick Guide

1. **Fork & Clone** the repository
2. **Create a branch** following our [naming conventions](#branch-naming)
3. **Make changes** following our [code standards](#code-standards)
4. **Write tests** and ensure they pass
5. **Commit** using our [commit conventions](#commit-messages)
6. **Submit a Pull Request**

## Development Workflow

```bash
# 1. Sync with upstream
git checkout main
git pull upstream main

# 2. Create feature branch
git checkout -b feat/your-feature-name

# 3. Make changes and test
# ... your development work ...

# 4. Commit changes
git commit -m "Web: your change description"

# 5. Push and create PR
git push origin feat/your-feature-name
```

## Branch Naming

Use descriptive branch names with these prefixes:

| Prefix      | Purpose           | Example                       |
| ----------- | ----------------- | ----------------------------- |
| `feat/`     | New features      | `feat/file-compression`       |
| `fix/`      | Bugfixes          | `fix/websocket-connection`    |
| `docs/`     | Documentation     | `docs/api-endpoints`          |
| `style/`    | Code formatting   | `style/rust-clippy-fixes`     |
| `refactor/` | Code refactoring  | `refactor/session-management` |
| `test/`     | Adding tests      | `test/websocket-handlers`     |
| `chore/`    | Maintenance tasks | `chore/update-dependencies`   |

## Commit Messages

```
Scope: <description>

[optional body]

[optional footer]
```

### Scopes

| Scope Options                                                                  | Example                     |
| ----------------------------------------------------------------------------- | --------------------------- |
| `Web`, `Server`, `iOS`, `Android`, `Desktop`, `Nginx`, `Docker`, `Scripts`, `Docs` | `Web: add dark mode toggle` |

### Examples

```bash
# Simple commits
git commit -m "Web: implement file drag and drop"
git commit -m "Server: handle websocket disconnection gracefully"
git commit -m "iOS: fix file picker"
git commit -m "Docs: update troubleshooting section"

# Detailed commit with body
git commit -m "Web: add real-time file transfer progress

- Implement progress bar component
- Add transfer speed calculation
- Update UI to show transfer status

Closes #123"
```

## Code Standards

### Rust (Server)

Toolchain version **1.98.0** (see `rust-toolchain`), edition 2024.

```bash
cd server
cargo fmt          # Format code
cargo clippy       # Check for issues
cargo test         # Run tests
```

**Requirements:**

- Address all `clippy` warnings (CI runs with warnings as errors)
- Write tests for new features
- Add documentation comments for public APIs

### Web (Angular)

Node **v24.16.0** (see `.nvmrc`).

```bash
cd client/web
npm run format     # Format code
npm run lint:fix   # Lint code
npm run test:ci    # Run tests
```

**Requirements:**

- Follow the Angular style guide
- Use TypeScript strict mode
- Use reactive programming with RxJS

### iOS (SwiftUI)

Requires macOS Tahoe 26.2+ and Xcode **26.5** (see `client/ios/.xcode-version`). Deployment target iOS 17.6+, Swift 6 language mode.

```bash
cd client/ios
swiftformat .          # Format code
swiftlint --fix        # Autocorrect lint issues
swiftlint lint --strict  # Lint code (CI runs this)
xcodebuild test \
  -project PastePoint.xcodeproj \
  -scheme PastePoint \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'  # Run tests
```

**Requirements:**

- Follow Swift API design guidelines
- Prefer `async/await` for concurrency
- Keep UI logic in SwiftUI views and business logic in separate types
- Match the CI-pinned tool versions — SwiftLint **0.65.0**, SwiftFormat **0.61.1** (see `.github/workflows/ios.yml`); CI asserts the exact versions
- Localize user-facing strings in `Localizable.xcstrings` using the symbolic `UPPER_SNAKE_CASE` keys shared with the web client
- Changes to the signaling, data-channel, or chunk protocol must stay wire-compatible with the web client — the two clients interoperate

**Running against a server:** the app needs a signaling server to do anything useful. Start one with `make dev` (Docker stack, reachable on 443) or `cd server && cargo run` (standalone, port 9000), then point the `DEBUG` host and `wsPort` in `PastePoint/Core/Config/AppEnvironment.swift` at it. Those are local-only values — do not commit them.

**Testing peer-to-peer flows** needs two peers: run two simulators, a simulator plus a device, or one simulator plus the web client in a browser. Web ↔ iOS is a valid pair, and it is the fastest way to catch a protocol regression.

### General Guidelines

- **Files**: kebab-case (`user-service.ts`) in Web, snake_case (`user_name.rs`) in Server, PascalCase (`UserService.swift`) on iOS, PascalCase (`UserService.kt`) on Android.
- **Variables**: camelCase (`userName`) in TypeScript, Swift, and Kotlin; snake_case (`user_name`) in Server
- **Constants**: UPPER_SNAKE_CASE in TypeScript, Rust, and Kotlin; lowerCamelCase in Swift
- **Comments**: Explain "why", not "what"
- **Error handling**: Always handle errors gracefully

## Building

```bash
# Web build
cd client/web && npm run build:dev

# Server build
cd server && cargo build

# iOS build
cd client/ios && xcodebuild build \
  -project PastePoint.xcodeproj \
  -scheme PastePoint \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Full stack via Docker Compose
make dev
```

## Adding a Dependency

Both clients ship their dependencies' licenses, from committed artifacts. After
adding, removing, or upgrading a dependency, regenerate and commit them:

```bash
# Web
cd client/web && npm run acknowledgements

# iOS (build in Xcode once first, so the SPM checkouts exist)
python3 scripts/acknowledgements/generate_ios_acknowledgements.py
```

CI fails when these are stale.

## Need Help?

- Check [existing issues](https://github.com/SloMR/pastepoint/issues)
- Read the project readme files
- Contact the maintainers

Thank you for contributing!
