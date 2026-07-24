# PastePoint Server (Rust Backend)

The PastePoint server is a Rust signaling backend built with Actix Web. It manages rooms and ephemeral identities, issues TURN credentials, and relays WebRTC signaling without handling file payloads.

[![Actix](https://img.shields.io/badge/Actix-4.13-blue)](https://actix.rs/)
[![OpenSSL](https://img.shields.io/badge/OpenSSL-0.10-yellow)](https://www.openssl.org/)
[![Sentry](https://img.shields.io/badge/Sentry-0.48-purple)](https://sentry.io/)
[![Rust](https://img.shields.io/badge/Rust-Backend-orange)](https://www.rust-lang.org/)

## Tech Stack

- **Framework**: [Actix Web](https://actix.rs/) - High-performance async web framework
- **WebSockets**: [`actix-ws`](https://crates.io/crates/actix-ws) — each connection is an async task (no actors); shared room state lives behind a cloneable handle
- **Security**: [OpenSSL](https://www.openssl.org/) for TLS termination
- **Serialization**: [Serde](https://serde.rs/) for JSON handling
- **UUID**: UUID generation for session management
- **Rate Limiting**: [Actix-governor](https://github.com/AaronErhardt/actix-governor) for request throttling
- **Logging**: Built-in logging with configurable levels
- **Error Tracking**: [`sentry`](https://sentry.io/) + `sentry-actix` with privacy-tight redaction (off by default in dev)

## Project Structure

```
server/
├── src/                           # Source code
├── config/                        # Configuration files
│   ├── development.toml           # Development configuration
│   ├── production.toml            # Production configuration
│   └── docker-dev.toml            # Docker development config
├── tests/                         # Tests
├── target/                        # Rust build artifacts
├── Cargo.toml                     # Project dependencies
├── Cargo.lock                     # Dependency lock file
├── Dockerfile                     # Docker configuration
└── README.md                      # Project documentation
```

## Quick Start

### Prerequisites

- **Rust**: 1.93.1 (specified in `../rust-toolchain`, edition 2024)
- **OpenSSL**: Required for SSL/TLS support
  - Linux: `sudo apt-get install libssl-dev pkg-config`
  - macOS: `brew install openssl pkg-config`
  - Windows: `winget install OpenSSL`

### Development Setup

1. **Navigate to server directory**:

   ```bash
   cd server
   ```

2. **Generate the development certificate**:

   ```bash
   ../scripts/generate-certs.sh
   ```

3. **Build the server**:

   ```bash
   cargo build
   ```

4. **Run the development server**:

   ```bash
   cargo run
   ```

## Configuration

### Configuration Files

- `config/development.toml`: Development environment settings
- `config/production.toml`: Production environment settings
- `config/docker-dev.toml`: Docker development environment settings

The active config is selected via the `RUN_ENV` environment variable (e.g.
`RUN_ENV=development`, `production`, or `docker-dev`), defaulting to the
development configuration when unset. The `docker-dev` configuration is used
inside Docker Compose and expects container certificate paths.

## Testing

### Run all tests:

```bash
cargo test
```

### Run specific test:

```bash
cargo test test_name
```

### Run tests with output:

```bash
cargo test -- --nocapture
```

## Development Guide

### Code Quality

- **Formatting**: `cargo fmt`
- **Linting**: `cargo clippy`
- **Security audit**: `cargo audit`

### Development Commands

```bash
# Build for development
cargo build

# Build for production
cargo build --release
```

## Security Features

- **TLS/SSL**: Full SSL/TLS support with configurable certificates
- **Rate Limiting**: Configurable request throttling with Actix-governor
- **CORS**: Configurable Cross-Origin Resource Sharing
- **Input Validation**: Comprehensive input validation and sanitization
- **Session Management**: Secure UUID-based session handling
- **WebSocket Security**: TLS, origin validation, and room-scoped signaling relay

## Troubleshooting

### Common Issues

1. **SSL Certificate Errors**:

   ```bash
   # Generate self-signed certificates
   ../scripts/generate-certs.sh
   ```

2. **Port Already in Use**:

   ```bash
   # Check what's using the port
   lsof -i :9000
   # Kill the process or change the port in config
   ```

3. **Permission Denied**:

   ```bash
   # Ensure proper permissions for SSL certificates
   sudo chown -R $USER:$USER /path/to/certs
   ```

4. **Build Issues**:
   ```bash
   # Clean build artifacts
   cargo clean
   # Rebuild
   cargo build
   ```

## Contributing

- [Contributing](../CONTRIBUTING.md)

## License

This project is licensed under the GPL-3.0 License. See the [LICENSE](../LICENSE) file for details.

## Related Documentation

- [Main project readme](../README.md)
- [Web client readme](../client/web/README.md)
- [iOS client readme](../client/ios/README.md)
- [Docker Compose setup](../docker-compose.yml)
