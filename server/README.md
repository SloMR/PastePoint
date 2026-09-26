# PastePoint Server

The PastePoint signaling server, written in Rust with Actix Web.

It names each WebSocket connection, groups connections into sessions and rooms, relays WebRTC signaling between peers in the same room, and issues TURN credentials. Chat messages and files never pass through it: peers send them to each other over WebRTC data channels.

Clients that share a public IP address land in the same public session. A private session is joined with a 10-character invite code instead.

The [root readme](../README.md) covers the whole project.

## Run the server

### Standalone

You need:

- Rust at the version in `rust-toolchain` at the repository root. rustup selects it anywhere in the repository. Dependencies and the edition are in `Cargo.toml`.
- OpenSSL development files and pkg-config, for the `openssl` crate:
  - Debian or Ubuntu: `sudo apt-get install libssl-dev pkg-config`
  - macOS: `brew install openssl pkg-config`
  - Windows: the `openssl-sys` build doesn't search install folders. Set `OPENSSL_DIR` to an OpenSSL install that includes the development files, or install OpenSSL through vcpkg.

Then:

```bash
cd server
../scripts/generate-certs.sh 192.168.1.100   # your LAN IP address; omit it for localhost only
cargo run
```

Run it from `server/`. The config path and the certificate paths in `development.toml` are relative to the working directory.

`generate-certs.sh` writes `certs/key.pem` and `certs/cert.pem` at the repository root. The certificate covers `localhost`, `127.0.0.1` and the address you pass, for 365 days.

The server listens on port 9000 and speaks HTTPS only. Check it:

```bash
curl -k https://127.0.0.1:9000/health   # PastePoint Server is running!
```

Clients reach a standalone server at `wss://<host>:9000/ws`, and a Docker stack at `wss://<host>/ws` through nginx.

### Docker

Start the stack as the [root readme](../README.md) describes. For the server container:

- Docker Compose builds `server/Dockerfile` with the repository root as the build context.
- `RUST_BUILD_MODE` (`debug` or `release`) picks the Cargo build profile.
- `RUN_ENV` is set from `SERVER_ENV` in `.env.development` or `.env.production`.
- `TURN_SECRET` is passed through from the same file.
- The certificate folder (`CERT_PATH`) is mounted read-only at `/etc/ssl/pastepoint`, the path in `docker-dev.toml` and `production.toml`.
- The container joins group `TLS_KEY_GID` (default 1500) to read `key.pem`.
- The config files are copied into the image. Rebuild after you edit one; `make dev` and `make prod` rebuild.
- Port 9000 is open only on the internal network. nginx forwards `/ws`, `/ws/{code}`, `/create-session`, `/version` and `/turn-credentials` to it. Other paths, including `/health`, go to the web app.
- The health check requests `https://127.0.0.1:9000/health` inside the container. The SSR and nginx containers wait for it to pass.
- The process runs as the non-root user `appuser`.

## Configuration

### Environments

`RUN_ENV` selects `config/<RUN_ENV>.toml`. When it is unset, the server uses `development`.

| Command     | `RUN_ENV`    | Config file               | Client address taken from           |
| ----------- | ------------ | ------------------------- | ----------------------------------- |
| `cargo run` | unset        | `config/development.toml` | TCP peer address                    |
| `make dev`  | `docker-dev` | `config/docker-dev.toml`  | TCP peer address, which is nginx    |
| `make prod` | `production` | `config/production.toml`  | `X-Forwarded-For`, then `X-Real-IP` |

The Docker values come from `SERVER_ENV` in the example `.env` files.

`development` and `docker-dev` are development mode: the server uses the TCP peer address. Any other value is production mode: the server trusts only the forwarding headers that nginx sets, and refuses requests without them. The client address keys the public session, the rate limit and the unjoined-code cap.

The config file and its `[server]` table are required. Without them, startup fails with `Failed to load server configuration`. The other tables are optional. Without them, Sentry and TURN are off, and `/version` serves empty values.

### Keys

`[server]`:

| Key                     | Meaning                                                                                                              |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `bind_address`          | Address and port to listen on, over HTTPS.                                                                           |
| `key_file_path`         | PEM private key.                                                                                                     |
| `cert_file_path`        | PEM certificate chain.                                                                                               |
| `auto_join`             | `true`: each connection joins the room `main` right after it gets its name. `false`: clients send `/join`.           |
| `rate_limit_per_second` | Requests per second added back to each client's allowance.                                                           |
| `rate_limit_burst_size` | Size of each client's allowance. Past it, requests get 429.                                                          |
| `log_level`             | Log filter, such as `info` or `debug`. `RUST_LOG` overrides it. Defaults to `debug`.                                 |
| `cors_allowed_origins`  | The only browser origin allowed, such as `https://pastepoint.com`. It must match exactly. See [Pitfalls](#pitfalls). |

`[client_version.ios]` and `[client_version.web]`, served by `GET /version`. The server only serves these values; each client compares them with its own version.

| Key       | Meaning                                                          |
| --------- | ---------------------------------------------------------------- |
| `minimum` | Clients below it must update, and stop connecting until they do. |
| `latest`  | Clients below it are offered an update.                          |
| `url`     | Where the update is. Without it, clients ignore the policy.      |

Empty values mean no policy. Clients also ignore the policy when `minimum` is above `latest`. Raise `minimum` only after that build is live, or users are locked out.

`[sentry]`:

| Key                  | Meaning                                                                             |
| -------------------- | ----------------------------------------------------------------------------------- |
| `enabled`            | Turns Sentry on, together with a non-empty `dsn`.                                   |
| `dsn`                | Project ingest address. It is committed on purpose: a DSN is public, not a secret.  |
| `environment`        | Environment name shown in Sentry.                                                   |
| `sample_rate`        | Share of error events sent, from 0.0 to 1.0. Defaults to 1.0.                       |
| `traces_sample_rate` | Share of transactions sent. Defaults to 0.1. `GET /ws` handshakes are never traced. |

Only this table controls Sentry. Setting `SENTRY_DSN` has no effect.

`[turn]`:

| Key           | Meaning                                                 |
| ------------- | ------------------------------------------------------- |
| `urls`        | TURN server URLs sent to clients.                       |
| `ttl_seconds` | How long each credential stays valid. Defaults to 1800. |

The shared secret comes from `TURN_SECRET`. Never put it in these files; they are committed. The relay's coturn `static-auth-secret`, with `use-auth-secret` on, must match it exactly.

### Environment variables

| Variable      | Effect                                                                                                    |
| ------------- | --------------------------------------------------------------------------------------------------------- |
| `RUN_ENV`     | Selects the config file and the mode. See [Environments](#environments).                                  |
| `TURN_SECRET` | TURN shared secret. When it is unset or empty, `/turn-credentials` answers 204 and clients use STUN only. |
| `RUST_LOG`    | Log filter in `env_logger` syntax. Overrides `log_level`.                                                 |

Debug builds also load `.env.development`, searching from the working directory upward. A `cargo run` in `server/` therefore reads the file at the repository root. Variables already set in your shell win. The server ignores that file's `SERVER_ENV`; only Docker Compose reads it.

### Pitfalls

- `cors_allowed_origins` gates WebSocket handshakes as well as CORS. Scheme, host and port must match. A browser WebSocket from any other origin, including a subdomain or another port, gets 403. `scripts/configure-network.sh` sets it to your LAN IP address in `development.toml` and `docker-dev.toml`.
- Production mode needs nginx in front. Without the forwarding headers, `/ws` answers 400 and `/create-session` answers 403.
- In `docker-dev`, every request comes from nginx's address. All clients share one public session and one rate-limit allowance.
- `/version` answers carry `Cache-Control: public, max-age=300`, so clients can keep an old policy for 5 minutes.

## HTTP routes

All routes are `GET`. Every request counts against the client's rate limit; past it, the answer is 429 with a `retry-after` header. CORS allows `GET` and `OPTIONS` from `cors_allowed_origins`, with credentials.

| Route               | Answer                                                                                                                |
| ------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `/`                 | 302 to `/health`.                                                                                                     |
| `/health`           | 200 `PastePoint Server is running!`                                                                                   |
| `/version`          | 200 JSON: `ios` and `web`, each with `minimum`, `latest` and `url`. Cached for 5 minutes.                             |
| `/turn-credentials` | 200 JSON: `username`, `credential`, `ttl`, `urls`. Not cached. 204 when TURN is off.                                  |
| `/create-session`   | 200 JSON: `code`, a new private session code. See the refusals below.                                                 |
| `/ws`               | WebSocket into the public session of the client's IP address. See [Handshake](#handshake).                            |
| `/ws/{code}`        | WebSocket into the private session `code`. 404 `Unknown session code` when the code is malformed, unknown or expired. |

`/create-session` refuses with:

- 403 for a cross-site browser request (`Sec-Fetch-Site: cross-site`). Native clients don't send that header.
- 403 in production mode when the forwarding headers are missing.
- 429 when the client already holds 20 codes nobody has joined.
- 503 when the server holds 100,000 sessions.

TURN credentials use the TURN REST scheme: `username` is `<Unix expiry time>:pastepoint`, and `credential` is the base64 HMAC-SHA1 of `username`, keyed with the secret.

## WebSocket protocol

### Sessions, rooms and names

- `/ws` joins the public session of the client's IP address. `/ws/{code}` joins a private session.
- A session holds rooms. The room `main` stays even when empty. Other rooms are removed when their last member leaves.
- Each connection gets a random first and last name, unique among live connections. A reconnect gets a new name. There are no accounts.
- A public session ends when its last client leaves. A private session keeps its code for 60 seconds after its last client leaves, so its clients can reconnect.
- `[SystemName]` is the first frame on every connection, before the auto-join. Peers can address a client as soon as it joins a room, so its name must arrive first. `name_arrives_before_the_room_join` in `ws_messages_tests.rs` keeps this order.

### Handshake

The server checks, in order:

1. The request is a WebSocket upgrade. Otherwise: 400.
2. If there is an `Origin` header, it matches `cors_allowed_origins`. Otherwise: 403. Native clients send no `Origin`.
3. `/ws` in production mode: a forwarding header is present. Otherwise: 400.
4. `/ws`: a `User-Agent`, if sent, has at least 5 characters and doesn't contain `bot` in any case. Otherwise: 403.
5. `/ws/{code}`: the code is 10 characters from the code alphabet and exists. Otherwise: 404.

Clients send text frames that start with a prefix. The server ignores binary frames.

### Messages from the server

| Message                          | Sent to                                            | When                                                                                  |
| -------------------------------- | -------------------------------------------------- | ------------------------------------------------------------------------------------- |
| `[SystemName] <name>`            | The client                                         | First, on every connection. Also in reply to `/name`.                                 |
| `[SystemRooms] <room>, <room>`   | Every client in the session                        | A room is created, or someone leaves a room. Also to the client, in reply to `/list`. |
| `[SystemMembers] <name>, <name>` | Every client in the room                           | Someone joins or leaves the room.                                                     |
| `<name> [SystemJoin] <room>`     | Every client in the room, including the new member | Someone joins the room. The prefix is in the middle.                                  |
| `[SignalMessage] <json>`         | The target peer                                    | A peer sent it a signal.                                                              |
| `[SystemError] <text>`           | The client                                         | A message was refused.                                                                |

Lists are sorted and separated by a comma and a space. Names contain a space.

### Messages from the client

| Message                      | Effect                                                  |
| ---------------------------- | ------------------------------------------------------- |
| `[SignalMessage] <json>`     | Relays a signal. See [Signals](#signals).               |
| `[UserCommand] /list`        | Replies with `[SystemRooms]`.                           |
| `[UserCommand] /join <room>` | Moves the client to `<room>`, and creates it if needed. |
| `[UserCommand] /name`        | Replies with `[SystemName]`.                            |
| `[UserDisconnected]`         | Leaves the current room. The connection stays open.     |
| `[KeepAlive]`                | Ignored.                                                |

Anything else gets `[SystemError] Error Unknown command: Not Found`. Room names are 1 to 64 letters, digits, hyphens, underscores or spaces.

### Signals

A signal is a JSON object. The server needs only `to`:

| Field              | Handling                                                                                                        |
| ------------------ | --------------------------------------------------------------------------------------------------------------- |
| `to`               | Required, not empty. The name of the target peer.                                                               |
| `from`             | Replaced with the sender's name.                                                                                |
| `type`             | Relayed as is, and used to tag telemetry. Clients send `offer`, `answer`, `candidate` and `connection_request`. |
| `data`, `sequence` | Relayed without being read. `data` holds the SDP or the ICE candidate.                                          |

The server relays a signal only when the sender and the target share a room. Otherwise, and for a signal to yourself, it drops the signal without a reply. A signal that isn't JSON, or has no `to`, gets a `[SystemError]`.

### Limits

All limits are in `src/consts.rs`.

| Limit                     | Value                        | Constant                        | When exceeded                                                                              |
| ------------------------- | ---------------------------- | ------------------------------- | ------------------------------------------------------------------------------------------ |
| WebSocket frame           | 64 KiB                       | `MAX_FRAME_SIZE`                | `[SystemError] Invalid message format: Internal Server Error`, then the connection closes. |
| Fragmented message        | 256 KiB                      | `MAX_CONTINUATION_SIZE`         | Same.                                                                                      |
| Signal                    | 128 KiB                      | `MAX_SIGNAL_SIZE`               | `[SystemError] Signal message too large`                                                   |
| Text frames from a client | 30 per second per connection | `MAX_WS_MESSAGES_PER_SEC`       | Dropped without a reply.                                                                   |
| Queued frames to a client | 256 per connection           | `OUTBOUND_CHANNEL_CAPACITY`     | Dropped.                                                                                   |
| Rooms per session         | 50                           | `MAX_ROOMS_PER_SESSION`         | `[SystemError] Room limit or session limit reached`                                        |
| Sessions                  | 100,000                      | `MAX_SESSIONS`                  | `/create-session` answers 503. A join in a new session gets the error above.               |
| Unjoined codes per client | 20                           | `MAX_UNJOINED_CODES_PER_CLIENT` | `/create-session` answers 429.                                                             |

### Timing

| What                               | Value                                                                                  | Constant                  |
| ---------------------------------- | -------------------------------------------------------------------------------------- | ------------------------- |
| Server ping                        | Every 5 seconds.                                                                       | `HEARTBEAT_INTERVAL`      |
| Silent connection closed           | After 15 seconds without a ping or pong from the client, checked at each server ping.  | `HEARTBEAT_TIMEOUT`       |
| Private code with nobody connected | Removed after 60 seconds, both before the first join and after the last client leaves. | `SESSION_EXPIRATION_TIME` |
| Sweep of empty sessions            | Every hour.                                                                            | `CLEANUP_INTERVAL`        |

Text frames, including `[KeepAlive]`, don't count as signs of life. A connection that dies without closing, such as after a Wi-Fi drop, stays in member lists for up to about 20 seconds. It then closes with the `ws.disconnected` reason `heartbeat_timeout`.

## Security and privacy

- The server speaks HTTPS only, with Mozilla's intermediate TLS settings. In Docker, nginx terminates the client's TLS and connects to the server over HTTPS.
- Identity comes from the connection. The server writes `from` on every signal it relays, so a client can't sign as another peer.
- Signals reach only peers in the same room.
- A private session needs its code. Codes are 10 characters from a 57-character alphabet without look-alikes (no `I`, `O`, `l`, `0` or `1`), about 58 bits, drawn from `rand::rng()`, a cryptographic random generator.
- `/ws/{code}` accepts only codes, so a public session can't be joined from another network.
- Codes nobody joins expire after 60 seconds, and each client can hold at most 20 of them. `/create-session` refuses cross-site browser requests.
- The CORS and WebSocket `Origin` checks allow one exact origin. Native clients send no `Origin`.
- HTTP rate limits are per client IP address, with IPv6 grouped by its /56 prefix. In production mode, nginx overwrites `X-Forwarded-For` and `X-Real-IP`, and the server reads the last `X-Forwarded-For` value.
- All state is in memory. A restart drops every session, room and code.

The legal and privacy text is in [DISCLAIMER.md](../DISCLAIMER.md).

### Logs and Sentry

- The access log shows the matched route, not the path: `GET /ws/{code} 101 <bytes> <seconds>`. Codes and client addresses never appear in it.
- In production mode, logs at `info` and above carry no names, codes, IP addresses or payloads. That detail is logged at `debug` only.
- Log levels map to Sentry: `error` becomes an issue, `warn` becomes a Sentry log and a breadcrumb, and `info` becomes a breadcrumb. `debug` and `trace` stay local.
- `send_default_pii` is off. Before an event leaves the process, `before_send` removes the server name and the request URL, headers, cookies, query string and body, and sets the user IP address to `127.0.0.1`.

Telemetry carries counts and kinds only:

| Name              | Type        | Attributes                                                 |
| ----------------- | ----------- | ---------------------------------------------------------- |
| `version.check`   | Log         | `platform`: `ios`, `web` or `other`, from the `User-Agent` |
| `session.created` | Log         | `kind`: `public` or `private`                              |
| `room.joined`     | Log         | `room_size`                                                |
| `ws.disconnected` | Log         | `reason`, such as `client_close` or `heartbeat_timeout`    |
| `sessions.active` | Log, hourly | `count`                                                    |
| `signaling.relay` | Transaction | Tag `signal.type`                                          |

## Tests

- Tests live in `server/tests/` and use only the public API of the `server` crate. There are no inline `#[cfg(test)]` modules. Add a test to the file for its area, or create a new file.
- When a test needs a knob, add a small public one. `SessionStore::with_expiration` is an example: it lets `session_store_tests.rs` expire codes in milliseconds.
- `tests/common/mod.rs` provides `init_test_server(auto_join)`, an in-process server with the `/ws` route, and helpers that connect, send text and wait for a frame.
- Name each test as a sentence that says what it checks, such as `private_socket_refuses_an_unknown_code`.
- Tests load the config with `ServerConfig::load`, so leave `RUN_ENV` unset. In production mode, the WebSocket tests fail for lack of forwarding headers.

| File                     | Covers                                                                                                             |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------ |
| `http_routes_tests.rs`   | `/`, `/health`, CORS, the `/create-session` cross-site check                                                       |
| `ws_handshake_tests.rs`  | Public and private upgrades, unknown codes, a public key on the private route, cross-site origins                  |
| `ws_messages_tests.rs`   | Name first, `/name`, `/list`, `/join`, several clients, the relayed `from`, errors for bad messages, binary frames |
| `session_store_tests.rs` | Public session keys, code expiry, the reconnect grace period, unjoined-code caps, unique names                     |
| `chat_server_tests.rs`   | Room membership                                                                                                    |
| `rate_limit_tests.rs`    | Per-client rate-limit keys                                                                                         |
| `origin_check_tests.rs`  | `ServerConfig::check_origin`                                                                                       |

Run one file with `cargo test --test session_store_tests`, or the tests whose names contain a word with `cargo test <word>`. The checks to run before you push are in [CONTRIBUTING.md](../CONTRIBUTING.md).

## Troubleshooting

### Certificate errors

Regenerate the certificate with the address that clients use, from `server/`: `../scripts/generate-certs.sh <lan-ip>`. It covers `localhost`, `127.0.0.1` and that address.

### The web client can't connect to a standalone server

- A 403 on the WebSocket handshake means the page's origin isn't `cors_allowed_origins`. Run `scripts/configure-network.sh`, or edit the key.
- Browsers don't prompt for a self-signed certificate on a WebSocket. Open `https://<host>:9000/health` once and accept the certificate.

### `/ws` answers 400 and `/create-session` answers 403 without nginx

`RUN_ENV` is set to something other than `development` or `docker-dev`, so the server expects nginx's forwarding headers. Unset `RUN_ENV` for a standalone run.

### `Failed to load server configuration` at startup

There is no `config/<RUN_ENV>.toml` under the working directory. Run from `server/`, and check `RUN_ENV`.

### `Cannot find private key file` or `Cannot find certificate chain file`

The certificate paths in the config don't exist or can't be read. Generate the certificates, or fix `key_file_path` and `cert_file_path`.

### The Docker stack stops at `cert-checker` on Linux

The containers read `key.pem` through group `TLS_KEY_GID` (default 1500). For the development key, from the repository root:

```bash
sudo chgrp 1500 certs/key.pem
sudo chmod 640 certs/key.pem
```

Don't change the key's group to your own: the containers would lose access. A standalone run only needs you to own the key, which `generate-certs.sh` already sets. A production key in `/etc/ssl/pastepoint` needs the same group and mode. Docker Desktop doesn't enforce file modes.

### Port 9000 is already in use

Find the process with `lsof -i :9000`. Stop it, or change `bind_address`.

### Visual Studio Code says the toolchain is too old for rust-analyzer

Add the component to the pinned toolchain, then restart the editor:

```bash
rustup component add rust-analyzer   # run inside the repository
```

Don't add it to `rust-toolchain`. `server/Dockerfile` and CI use that file, and only the editor needs the component.

## Related documentation

- [Project overview and Docker quick start](../README.md)
- [Contributing, with the checks to run before you push](../CONTRIBUTING.md)
- [Legal and privacy text](../DISCLAIMER.md)
- [Web client](../client/web/README.md)
- [iOS client](../client/ios/README.md)

The server is licensed under GPL-3.0. See [LICENSE](../LICENSE).
