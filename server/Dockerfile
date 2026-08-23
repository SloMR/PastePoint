# syntax=docker/dockerfile:1.5
# Stage 1: Build the Rust app (Alpine for musl-linked binary)
FROM rust:1.98.0-alpine AS builder
WORKDIR /usr/src/app

ARG RUST_BUILD_MODE=release

# Install build dependencies (Alpine/musl)
# hadolint ignore=DL3018
RUN apk add --no-cache openssl-dev openssl-libs-static musl-dev pkgconf

# Statically link OpenSSL so runtime image doesn't need libssl
ENV OPENSSL_STATIC=1 OPENSSL_NO_VENDOR=1

# Copy manifests and sources
COPY server/Cargo.toml server/Cargo.lock ./
COPY rust-toolchain rust-toolchain
COPY server/src ./src
COPY server/config ./config

# Build. The target/ cache mount keeps compiled dependencies across builds, so a
# source-only change recompiles just the server crate instead of the whole tree.
# target/ is not visible to later stages, so the binary is copied out within this
# same RUN. Stripping is handled by `strip = true` in Cargo.toml's release profile.
RUN --mount=type=cache,target=/usr/local/cargo/registry \
  --mount=type=cache,target=/usr/local/cargo/git/db \
  --mount=type=cache,target=/usr/src/app/target,sharing=locked \
  set -eux; \
  if [ "$RUST_BUILD_MODE" = "release" ]; then \
  cargo build --release; \
  cp target/release/server_bin /usr/src/app/server_bin; \
  else \
  cargo build; \
  cp target/debug/server_bin /usr/src/app/server_bin; \
  fi

# Stage 2: Create a minimal runtime image
FROM alpine:3.21

WORKDIR /usr/local/bin

# Install only runtime dependencies
# hadolint ignore=DL3018
RUN apk add --no-cache ca-certificates wget

# Copy only the built binary from the builder stage
COPY --from=builder /usr/src/app/server_bin .

# Copy the config files into the final image
COPY server/config ./config

# Create a non-root user
RUN adduser -D appuser
USER appuser

# Add healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null --no-check-certificate https://127.0.0.1:9000/health || exit 1

# Set the command to run the binary
CMD ["./server_bin"]