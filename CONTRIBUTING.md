# Contributing to PastePoint

Setup instructions live in the readmes: [project](README.md), [server](server/README.md), [web](client/web/README.md) and [iOS](client/ios/README.md). This guide covers the checks CI runs, the commit and pull request conventions, and the project rules that are easy to miss.

## Workflow

1. Fork the repository on GitHub and clone your fork.
2. Add the upstream remote:

   ```bash
   git remote add upstream https://github.com/SloMR/PastePoint.git
   ```

3. Branch from the latest `main`. Use a `feat/`, `fix/`, `chore/`, `ci/` or `docs/` prefix, optionally followed by the component, as in `fix/ios/photos-save-date`:

   ```bash
   git fetch upstream
   git switch -c fix/short-description upstream/main
   ```

4. Make your change and run the checks below for every component you touched.
5. Open a pull request against `main`.

## Before you push

These are the commands CI runs. CI adds flags that don't change the result, such as `--verbose` and GitHub report formats.

Use the pinned toolchains: `rust-toolchain` for Rust, `.nvmrc` for Node.js and `client/ios/.xcode-version` for Xcode.

### Server

From `.github/workflows/server.yml`:

```bash
cd server
cargo fmt -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --all
cargo build --release
```

### Web

From `.github/workflows/web.yml`:

```bash
cd client/web
npm ci
npm run lint
npm run knip
npm run format:check
npm run acknowledgements:check
npm run test:ci
npm run build -- --configuration=production
npm run csp:check
```

- `test:ci` runs the tests in headless Chrome, so Chrome must be installed.
- `csp:check` reads the production build, so run it after the build.
- `npm run format` and `npm run lint:fix` fix most formatting and lint problems.

### iOS

From `.github/workflows/ios.yml`:

```bash
cd client/ios
swiftlint lint --strict
swiftformat --lint .
periphery scan --strict
xcodebuild build \
  -project PastePoint.xcodeproj \
  -scheme PastePoint \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -skipMacroValidation \
  -skipPackagePluginValidation \
  ARCHS=arm64 \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
cd ../..
python3 scripts/acknowledgements/generate_ios_acknowledgements.py --check
```

- CI also builds Release for devices. Repeat the `xcodebuild` command with `-configuration Release -destination 'generic/platform=iOS'`.
- CI checks the exact SwiftLint, SwiftFormat and Periphery versions set in `ios.yml` (`SWIFTLINT_VERSION`, `SWIFTFORMAT_VERSION`, `PERIPHERY_VERSION`). Install the same versions.
- `--strict` turns warnings into errors, so the warning limits in `.swiftlint.yml` are hard limits.
- There are no iOS unit tests yet. `PastePointTests` is still Xcode's template, so CI only builds.

### Whole repository

- super-linter (`.github/workflows/linter.yml`) runs on every push and pull request and lints the whole repository. It checks every language it supports, except the validators that file turns off. That includes shell scripts, Python, Dockerfiles, YAML and GitHub Actions workflows.
- Markdown goes through a terminology check (textlint). Write names exactly: GitHub, Node.js, npm, Xcode, Wi-Fi.
- CI builds none of the Docker images and never loads the nginx config. After changing `nginx/`, a Dockerfile or `docker-compose.yml`, run `make dev` and check that `server`, `ssr` and `nginx` report healthy in `docker compose --env-file .env.development ps`.

## Commits

The subject is `Scope: Imperative sentence`.

- Scopes: `Server`, `Web`, `iOS`, `Nginx`, `Docker`, `Scripts`, `CI`, `Docs`.

Subjects from the history:

```text
Server: Refuse cross-site requests to create a session
Nginx: Stop forwarding Referer to the backend
CI: Run Periphery in the iOS workflow
```

A commit with a body:

```text
Web: Hide the Accept and Decline buttons as soon as one is tapped

- The buttons stayed until the accept was sent, so a second tap could send a second `file-accept`

- `acceptFileOffer` also ignores a file that is already accepted
```

## Pull requests

- Target `main`.
- The title is a commit subject, such as `iOS: Fix Xcode 27 errors`. When the pull request spans components, use a plain sentence instead, such as `Harden security and privacy across the server, web, iOS and nginx`.
- The body has two sections:

  ```markdown
  ### Summary

  A few plain sentences on what the change does and what it replaces.

  ### What changed

  - One line per change
  ```

- Pull requests are merged with a merge commit, so every commit lands on `main` as you wrote it.

## Project rules

- **Wire compatibility.** The web and iOS clients speak the same protocol. A change to signaling, data-channel messages or the file chunk format must land on both clients. Test it with one web peer and one iOS peer.
- **New server routes.** Add a `location` block to `nginx/locations.conf`, or nginx sends the request to the SSR server. If its configuration includes a host, make `scripts/configure-network.sh` rewrite that host too.
- **Inline scripts.** The Content Security Policy allows inline scripts by hash. After changing an inline `<script>` in `client/web/src/index.html`, run `npm run csp:check` and add the hash it prints to `$script_src` in `nginx/security/security_headers.conf`.
- **Web strings.** Add every key to all six files in `client/web/src/app/core/i18n/localizations/`. Edit them as text: writing a file back through a JSON serializer drops the empty lines before the `_*_SECTION` keys.
- **iOS strings.** Add them to `client/ios/PastePoint/Resources/Localization/Localizable.xcstrings` in Xcode, using the same key as the web client.
- **Dependencies.** After adding, removing or upgrading one, regenerate the acknowledgements and commit them. CI fails when they are stale.
  - Web: run `npm run acknowledgements` in `client/web`.
  - iOS: build the app in Xcode once, so the package checkouts exist, then run `python3 scripts/acknowledgements/generate_ios_acknowledgements.py`.
- **Prettier.** `client/web/package.json` pins Prettier to the version super-linter bundles. Upgrade the two together, or super-linter and `npm run format:check` disagree.
- **Server tests** go in `server/tests/`, not in inline `#[cfg(test)]` modules.
- **Local-only changes.** `scripts/configure-network.sh` writes your local IP address into `client/web/src/environments/environment.ts`, `environment.docker-dev.ts`, `client/ios/PastePoint/Core/Config/AppEnvironment.swift`, `server/config/development.toml` and `docker-dev.toml`. Don't commit those edits. The same goes for the iOS `wsPort` value: `nil` for Docker Compose, `9000` for `cargo run`.

## Security

Report security problems in [GitHub Issues](https://github.com/SloMR/PastePoint/issues), or by email to [support@pastepoint.com](mailto:support@pastepoint.com).

## License

PastePoint is licensed under GPL-3.0-only (see [LICENSE](LICENSE)). Contributions are accepted under the same license. Swift files start with a copyright and `SPDX-License-Identifier: GPL-3.0-only` header. Copy it into new Swift files.
