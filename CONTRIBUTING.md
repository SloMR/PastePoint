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

Toolchain version **1.93.1** (see `rust-toolchain`), edition 2024.

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

Requires macOS + Xcode. CI runs only on `client/ios/**` changes. Build and test with the standard `xcodebuild` scheme.

**Requirements:**

- Follow Swift API design guidelines
- Prefer `async/await` for concurrency
- Keep UI logic in SwiftUI views and business logic in separate types

### General Guidelines

- **Files**: kebab-case (`user-service.ts`) in Web, snake_case (`user_name.rs`) in Server, PascalCase (`UserService.swift`) on iOS, PascalCase (`UserService.kt`) on Android.
- **Variables**: camelCase (`userName`) in TypeScript, Swift, and Kotlin; snake_case (`user_name`) in Server
- **Constants**: UPPER_SNAKE_CASE (`MAX_FILE_SIZE`)
- **Comments**: Explain "why", not "what"
- **Error handling**: Always handle errors gracefully

## Building

```bash
# Web build
cd client/web && npm run build:dev

# Server build
cd server && cargo build

# Full stack via Docker Compose
make dev
```

## Need Help?

- Check [existing issues](https://github.com/SloMR/pastepoint/issues)
- Read the project readme files
- Contact the maintainers

Thank you for contributing!
