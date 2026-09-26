# PastePoint web client

The Angular client for PastePoint, with server-side rendering (SSR).
It exchanges signaling messages with the Rust server over a WebSocket.
Chat and files go peer-to-peer over WebRTC data channels.
It speaks the same protocol as the iOS app.

For the project overview, see the [project readme](../../README.md).
Dependency versions are in `package.json`.

## Prerequisites

- Node.js: the version in `.nvmrc` at the repository root. With nvm, run `nvm use`. npm comes with Node.js.
- OpenSSL, to generate the development certificate.
- Google Chrome, for the unit tests.
- A backend: the Rust toolchain for a standalone server (see the [server readme](../../server/README.md)), or Docker for the full stack (see the [project readme](../../README.md)).

## Run locally

### Against a standalone server

1. Generate the development certificate, from the repository root:

   ```bash
   ./scripts/generate-certs.sh
   ```

   It writes `certs/`. The server and the development server both read it.

2. Start the server. It listens on port 9000.

   ```bash
   cd server
   cargo run
   ```

3. In a second terminal, install and start the client:

   ```bash
   cd client/web
   npm ci
   npm run start-local
   ```

4. Open `https://127.0.0.1` and accept the certificate warning.

Use `https://127.0.0.1`, not `https://localhost`. The server accepts a WebSocket only from the exact origin in `cors_allowed_origins` (`server/config/development.toml`). That origin is `https://127.0.0.1`.

`npm run start-local` listens on `0.0.0.0`, so `127.0.0.1` reaches it. `npm start` listens on `localhost` only, which Node.js can resolve to `::1`.

The development server uses port 443. It can't run next to the Docker Compose stack.

To test peer-to-peer features, open a second tab. Each tab gets its own connection and name.

### On your local network

To open the client from a phone or another computer:

1. From the repository root, run `./scripts/configure-network.sh` and enter your LAN IP. It writes the IP into `apiUrl` and `webUrl`, and into the server's `cors_allowed_origins`.
2. Generate a certificate that covers the IP: `./scripts/generate-certs.sh <ip>`.
3. Restart the server and `npm run start-local`, then open `https://<ip>`.

These edits are for your machine only. Don't commit them.

### With Docker Compose

Run `make dev` from the repository root. It builds and starts the Docker Compose stack, including the server, the SSR server and nginx.

- The client is built with the `docker-dev` configuration.
- nginx serves it on port 443. Open `https://127.0.0.1`.
- The containers don't watch for changes. Run `make dev` again after an edit.

The setup steps are in the [project readme](../../README.md).

## Configuration

### Build configurations

`angular.json` defines four build configurations. Each one uses an environment file from `src/environments/`.

| Configuration | Environment file            | Used by                                                    |
| ------------- | --------------------------- | ---------------------------------------------------------- |
| `development` | `environment.ts`            | `npm start`, `npm run start-local`, `npm run build:dev`    |
| `production`  | `environment.prod.ts`       | `npm run build`, `npm run build:prod`, `npm run watch`, CI |
| `docker`      | `environment.prod.ts`       | `make prod`                                                |
| `docker-dev`  | `environment.docker-dev.ts` | `make dev`                                                 |

The Docker Compose builds take the configuration name from `NPM_BUILD_CONFIG` in `.env.development` or `.env.production`.

### Environment fields

| Field                          | Meaning                                                                                              |
| ------------------------------ | ---------------------------------------------------------------------------------------------------- |
| `apiUrl`                       | Server host. It includes the port when no nginx is in front. The client adds `https://` or `wss://`. |
| `webUrl`                       | Host of invite links and QR codes. A scanned link must use this host.                                |
| `sentry.enabled`, `sentry.dsn` | Turn Sentry on. Both development files ship with it off.                                             |
| `production`                   | Production mode. The SSR server then serves plain HTTP, because nginx handles TLS.                   |

`logLevel`, `disableConsoleLogging`, `enableSourceMaps` and `disableFileDetails` configure ngx-logger.

| File                        | `apiUrl`                             | `webUrl`         |
| --------------------------- | ------------------------------------ | ---------------- |
| `environment.ts`            | `127.0.0.1:9000` (standalone server) | `127.0.0.1`      |
| `environment.docker-dev.ts` | `127.0.0.1` (nginx)                  | `127.0.0.1`      |
| `environment.prod.ts`       | `pastepoint.com`                     | `pastepoint.com` |

## Scripts

Run them from `client/web/`. For the checks to run before you push, see [CONTRIBUTING.md](../../CONTRIBUTING.md).

| Script                     | What it does                                                                |
| -------------------------- | --------------------------------------------------------------------------- |
| `npm start`                | Development server over HTTPS on port 443, on `localhost`                   |
| `npm run start-local`      | The same, on `0.0.0.0`                                                      |
| `npm run build`            | Production build, the default configuration                                 |
| `npm run build:dev`        | Development build                                                           |
| `npm run build:prod`       | Production build                                                            |
| `npm run watch`            | Production build that rebuilds on change                                    |
| `npm run serve:ssr:web`    | Runs the built SSR server                                                   |
| `npm test`                 | Unit tests in Chrome, rerun on change                                       |
| `npm run test:coverage`    | Unit tests with a coverage report in `coverage/`                            |
| `npm run test:ci`          | One headless test run with coverage                                         |
| `npm run lint`             | ESLint. `lint:fix` applies the fixes.                                       |
| `npm run knip`             | Finds unused files, exports and dependencies                                |
| `npm run format`           | Prettier. `format:check` only checks.                                       |
| `npm run acknowledgements` | Regenerates the third-party licenses. `acknowledgements:check` only checks. |
| `npm run csp:check`        | Checks the inline scripts of a build against the CSP                        |

`serve:ssr:web` listens on `HOST` and `PORT`, by default `127.0.0.1:443`. A development build serves HTTPS with the certificate in `certs/`. A production build serves plain HTTP.

## Rules

### Translations

- The strings are in `src/app/core/i18n/localizations/`: `en.json`, `ar.json`, `es.json`, `fr.json`, `ru.json` and `zh-CN.json`.
- Add every key to all six files. Keys are `UPPER_SNAKE_CASE`.
- Use the iOS key when the string also exists in the iOS app.
- Each section starts with a `_*_SECTION` entry. Add a key inside the matching section.
- Edit the files as text. Parsing and re-serializing a file removes the empty lines between sections.
- Check `git diff --numstat`. Each file should show one added line per key and no deletions.
- In a template, add `TranslatePipe` to the component's `imports` and write `{{ 'KEY' | translate }}`.
- In code, use `inject(TranslateService)` and `instant('KEY')`.
- A new language needs its JSON file and an entry in `LANGUAGES` in `src/app/core/i18n/languages.ts`. The entry's `direction` sets left-to-right or right-to-left.

### Content Security Policy

- nginx sends the policy. It is defined in `nginx/security/security_headers.conf`.
- `$script_src` has no `'unsafe-inline'`. It allows each inline script by its SHA-256 hash.
- Three scripts are hashed: the theme script and the `umamiBeforeSend` hook in `src/index.html`, and the `ng-event-dispatch-contract` script that Angular adds to the SSR page.
- After you change an inline script in `src/index.html`, or upgrade Angular, run `npm run build:prod` and then `npm run csp:check`. The check prints each hash to add to `$script_src`.
- Don't use inline event handlers such as `onclick=`. The policy blocks them, and the check fails on them.
- Keep `inlineCritical: false` in the `production` and `docker` configurations. Critical CSS inlining loads the style sheet with an `onload` handler.
- CI runs `csp:check` after its production build.

### Analytics

- The Umami tag is in `src/index.html`.
- `data-domains="pastepoint.com"` limits reporting to the production site. Development builds and forks don't report.
- The `umamiBeforeSend` hook replaces session codes in `/private/<code>` and `/ws/<code>` paths, in both the URL and the referrer.
- The CSP allows `cloud.umami.is` for the script and `gateway.umami.is` for requests.
- Changing the hook changes its hash. Update `$script_src` as described above.

### Tailwind CSS

- There is no `tailwind.config.js`. The theme is the `@theme` block in `src/styles.css`.
- Angular runs Tailwind CSS through PostCSS, configured in `.postcssrc.json`. Keep that file JSON: Angular reads only `.postcssrc.json` and `postcss.config.json`.
- Dark mode is class-based. The `dark` variant applies under the `dark` class, which the theme script in `src/index.html` sets on `<html>`.
- The default-palette shades in use are pinned to their Tailwind CSS v3 values in `@theme`. A shade that isn't pinned renders in the newer, more saturated palette. Pin any shade you start using.
- The `@layer base` rules keep two v3 defaults: gray-200 borders and a pointer cursor on buttons.

### Telemetry

- Sentry starts in `src/main.ts`. `src/app/app.config.ts` adds the error handler and tracing.
- Only those two files and `src/app/core/services/monitoring/` import `@sentry/*`. Other code injects `TelemetryService` from that folder.
- Sentry starts only when the environment file sets `sentry.enabled` and a `sentry.dsn`. It never starts during SSR.
- When Sentry is on, ngx-logger output reaches it: `info` as a breadcrumb, `warn` as a log and a breadcrumb, `error` as an issue.
- Keep chat text, filenames, room names, session codes, signaling payloads and IP addresses at `debug`.
- `sentry-scrubber.ts` redacts session codes in `/private/<code>` and `/ws/<code>` paths.
- The Sentry release is `web@<version>`, from `package.json`. The update gate compares the same `version` with the server's `GET /version` policy.

### Acknowledgements

- `public/legal/acknowledgements.json` lists the licenses of the production dependencies. The `/acknowledgements` page shows it.
- `npm run acknowledgements` generates it from `package-lock.json`. Regenerate and commit it after any dependency change.
- CI runs `npm run acknowledgements:check`, which fails when the file is stale.

## Troubleshooting

- **The server logs `WebSocket connection rejected: disallowed origin`.** The page's origin must equal `cors_allowed_origins` in `server/config/development.toml`, with the same scheme, host and port. Open `https://127.0.0.1`, or run `./scripts/configure-network.sh` for a LAN IP.
- **The page loads, but the WebSocket to port 9000 fails.** The browser may not trust the certificate on that port. Open `https://127.0.0.1:9000/health` once and accept it.
- **`https://127.0.0.1` doesn't load after `npm start`.** `npm start` listens on `localhost`, which Node.js can resolve to `::1`. Use `npm run start-local`.
- **The development server says port 443 is already in use.** The Docker Compose stack or another development server holds it. `make down` stops the stack.
- **`csp:check` says there is no build output.** Run `npm run build:prod` first.
- **`csp:check` asks you to add a hash.** Add it to `$script_src` in `nginx/security/security_headers.conf`.

## Related documentation

- [Project readme](../../README.md): overview and Docker Compose setup
- [CONTRIBUTING.md](../../CONTRIBUTING.md): checks to run before you push, and commit conventions
- [Server readme](../../server/README.md)
- [iOS client readme](../ios/README.md)
- [License](../../LICENSE): GPL-3.0
