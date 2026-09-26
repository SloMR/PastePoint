<div align="center">
  <img src="client/web/public/assets/pastepoint-light.svg" alt="PastePoint Logo" width="250"/>

<br>
<br>

![Docker](https://img.shields.io/badge/Docker-Containers-blue) ![Rust](https://img.shields.io/badge/Rust-Backend-orange) ![Angular](https://img.shields.io/badge/Angular-Frontend-red) [![iOS](https://img.shields.io/badge/iOS-SwiftUI-black)](https://developer.apple.com/ios/) [![Nginx](https://img.shields.io/badge/Nginx-Reverse_Proxy-green)](https://nginx.org)

</div>

# PastePoint

PastePoint sends chat messages and files between devices, peer to peer over WebRTC. Use it in a browser at [pastepoint.com](https://pastepoint.com) or in the iOS app. There are no accounts, and the server never sees your messages or files.

## How it works

- The Rust server gives each connection a random name, keeps rooms in memory and relays WebRTC setup messages (offers, answers and ICE candidates) between room members.
- Each client opens a WebRTC data channel to every other member. Chat and files travel over these encrypted channels, directly or through a TURN relay when a direct path fails.
- Devices that reach the server from the same IP address, usually the same Wi-Fi, share a room automatically. Devices on other networks join an invite-only room with a 10-character code, a QR code or an invite link.
- The web and iOS clients speak the same protocol, so they chat and share files with each other.

## Features

- **Same Wi-Fi**: devices on one network find each other with no setup.
- **Any network**: create an invite-only room and share its code, QR code or link. Invite links open the iOS app when it is installed.
- **Rooms**: create, list and switch rooms within a session.
- **Files**: send to the whole room or to one member. The receiver accepts or declines each file, both sides see progress and either side can cancel. The web client accepts drag and drop.
- **Integrity**: every file is checked against a BLAKE3 hash before it is saved.
- **Moderation**: incoming image previews stay blurred until revealed. You can block a member for the session, or report and block them by email.
- **Languages**: English, Arabic (right to left), Spanish, French, Russian and Simplified Chinese.
- **Clients**: a web app with server-side rendering and an app for iPhone and iPad, both with light and dark themes. An Android app is planned.

## Run locally with Docker

### Prerequisites

- Docker with Docker Compose v2 (the `docker compose` command)
- `make`, `bash` and `openssl`
- On Windows: Docker Desktop with WSL2. Run every command below in a WSL2 shell.

Node.js and Rust are needed only to run a component outside Docker, and Xcode only for the iOS app. See the [server](server/README.md), [web](client/web/README.md) and [iOS](client/ios/README.md) readmes. Toolchain versions are pinned in `.nvmrc` (Node.js), `rust-toolchain` (Rust) and `client/ios/.xcode-version` (Xcode).

### Use it on this computer

```bash
git clone https://github.com/SloMR/PastePoint.git
cd PastePoint
cp .env.development.example .env.development
./scripts/generate-certs.sh
make dev
```

Open `https://127.0.0.1` and accept the browser warning about the self-signed certificate. Don't use `localhost`: the server refuses browsers whose origin differs from `cors_allowed_origins` in `server/config/docker-dev.toml`.

On Linux, if `generate-certs.sh` prints a `sudo chgrp` command, run it so the containers can read the key (see [Certificate Management](#certificate-management)).

### Use it from other devices on your network

```bash
./scripts/configure-network.sh          # asks for this machine's local IP address
./scripts/generate-certs.sh <local-ip>
make dev
```

Then open `https://<local-ip>` on every device, this one included. `https://127.0.0.1` stops working because the allowed origin changes.

`configure-network.sh` writes the IP into `.env.development` and into five tracked files. Don't commit those changes:

- `client/web/src/environments/environment.ts`
- `client/web/src/environments/environment.docker-dev.ts`
- `client/ios/PastePoint/Core/Config/AppEnvironment.swift`
- `server/config/development.toml`
- `server/config/docker-dev.toml`

To point the iOS app at this stack, see the [iOS readme](client/ios/README.md).

### Make targets

| Command      | Effect                                            |
| ------------ | ------------------------------------------------- |
| `make dev`   | Build and start the stack with `.env.development` |
| `make prod`  | Build and start the stack with `.env.production`  |
| `make logs`  | Follow the container logs                         |
| `make stop`  | Stop the containers                               |
| `make down`  | Stop and remove the containers                    |
| `make certs` | Run `generate-certs.sh` for this machine only     |
| `make help`  | List the targets                                  |

`make` with no target runs `make prod`. `logs`, `stop` and `down` use `.env.development` when it exists and `.env.production` otherwise. To pick one, pass it: `make logs ENV_FILE=.env.production`.

## Deploy to production

These steps run the stack on a server. The committed production settings are for pastepoint.com. [Your own domain](#your-own-domain) lists what to change for another domain.

### Environment file

```bash
cp .env.production.example .env.production
chmod 600 .env.production
```

| Variable      | Value                                                                              |
| ------------- | ---------------------------------------------------------------------------------- |
| `SERVER_NAME` | Your domain. nginx serves it and redirects `www.` to it.                           |
| `CERT_PATH`   | Host directory that holds `cert.pem` and `key.pem` (default `/etc/ssl/pastepoint`) |
| `TLS_KEY_GID` | Group allowed to read `key.pem` (default 1500)                                     |
| `TURN_SECRET` | Shared secret of your TURN server. Leave it empty to run without one.              |

The other variables already hold production values. `.env.production` is gitignored; never commit it.

### Certificate Management

Put the certificate and private key for your domain in `CERT_PATH` as `cert.pem` and `key.pem`. The self-signed certificate from `generate-certs.sh` is for development only.

The server and nginx containers run as non-root users and read the key through the group `TLS_KEY_GID`. The key can then stay owned by root and unreadable by other users on the host:

```bash
sudo groupadd -g 1500 pastepoint-tls
sudo chgrp pastepoint-tls /etc/ssl/pastepoint/key.pem
sudo chmod 640 /etc/ssl/pastepoint/key.pem
```

- If group ID 1500 is taken, pick a free one and set `TLS_KEY_GID` to it.
- Apply the group and mode again after every certificate renewal.
- The `cert-checker` container runs first. If either file is missing or unreadable, it exits and the other containers don't start.
- Keep private keys out of Git. Files in `certs/` are gitignored.

### Your own domain

The server config and the web environment are built into the images. `make prod` rebuilds them on every run.

- `server/config/production.toml`
  - `cors_allowed_origins`: your origin, such as `https://example.com`. The server refuses browsers from any other origin.
  - `url` under `[client_version.web]`: where the web update prompt sends users.
  - `[sentry]`: set `enabled = false` or your own `dsn`. By default, errors go to PastePoint's Sentry project.
  - `urls` under `[turn]`: your TURN server.
- `client/web/src/environments/environment.prod.ts`
  - `apiUrl` and `webUrl`: your domain, without `https://`. The client connects to `apiUrl` and builds invite links on `webUrl`.
  - `sentry`: same as `[sentry]` above.
- `client/web/src/app/utils/constants.ts`: `SUPPORT_EMAIL`, where "Report and Block" sends reports.
- Optional: `client/web/src/index.html`, `client/web/public/robots.txt`, `client/web/public/sitemap.xml` and `client/web/src/app/core/services/ui/meta*.service.ts` use pastepoint.com in canonical and social-preview URLs. The Umami analytics tag in `index.html` reports only on pastepoint.com.
- The iOS app's host, Sentry DSN and support address are in `client/ios/PastePoint/Core/Config/AppEnvironment.swift`.

### TURN relay

Devices on different networks sometimes can't reach each other directly and need a TURN relay. PastePoint doesn't include one. Run a TURN server that accepts time-limited credentials derived from a shared secret (coturn's `use-auth-secret`). List its URLs under `[turn]` and put the secret in `TURN_SECRET`. With `TURN_SECRET` empty, `GET /turn-credentials` returns 204 and clients use STUN only.

### Ports

| Port | Service                                        | Published                 |
| ---- | ---------------------------------------------- | ------------------------- |
| 443  | nginx: the web app, `/ws` and the API routes   | Yes                       |
| 80   | nginx: redirects to HTTPS and serves `/health` | Yes                       |
| 9000 | Signaling server, over TLS                     | No, internal network only |
| 4000 | Server-side rendering (Express)                | No, internal network only |

### Start

```bash
make prod
```

Open ports 80 and 443 in the firewall. Follow the logs with `make logs`.

## Troubleshooting

- **The browser warns about the certificate.** This is expected with a self-signed certificate: accept it. For a LAN address, generate the certificate with that address: `./scripts/generate-certs.sh <local-ip>`.
- **The page loads but never connects.** Open the exact address from your config: `https://127.0.0.1`, or the IP you gave `configure-network.sh`. `make logs` shows `disallowed origin` when the server refuses the page.
- **`cert-checker` exits with "Missing or unreadable SSL certificates".** Generate the certificate, or give the key to the `TLS_KEY_GID` group. See [Certificate Management](#certificate-management).
- **nginx returns 502 Bad Gateway.** Set `HOST=0.0.0.0` in your env file. Older copies of `.env.development.example` had `127.0.0.1`, which nginx can't reach.

## Privacy and security

Chat and files travel between devices over encrypted WebRTC data channels; the server relays only connection setup and stores neither. Production builds send error reports to Sentry. [DISCLAIMER.md](DISCLAIMER.md) covers what is logged and what those reports contain.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the workflow, commit conventions and the checks to run before you push.

## License

This project is licensed under the GPL-3.0 License. See the [LICENSE](LICENSE) file for details.

## Contact

For issues or feature requests:

- [GitHub Issues](https://github.com/SloMR/pastepoint/issues)
- [sulaimanromaih@gmail.com](mailto:sulaimanromaih@gmail.com)
- [LinkedIn](https://www.linkedin.com/in/sulaiman-alromaih-845700202/)
