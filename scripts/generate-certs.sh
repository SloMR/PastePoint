#!/bin/sh
set -e

# Resolve certs/ relative to the repo root so the script works from any CWD
# (the Makefile runs it from the repo root, the docs from scripts/).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CERT_DIR="$SCRIPT_DIR/../certs"
LOCAL_IP="${1:-127.0.0.1}"
mkdir -p "$CERT_DIR"

# Generate self-signed cert for development
# Usage: ./generate-certs.sh [local-ip]
# Example: ./generate-certs.sh 192.168.1.100
openssl req -x509 -nodes -days 365 -newkey rsa:4096 \
    -keyout "$CERT_DIR/key.pem" \
    -out "$CERT_DIR/cert.pem" \
    -subj "/C=US/ST=State/L=City/O=PastePoint/CN=localhost" \
    -addext "subjectAltName=DNS:localhost,IP:127.0.0.1,IP:${LOCAL_IP}"

# Set secure permissions
OWNER_USER="${USER:-$(id -un)}"
OWNER_GROUP="$(id -gn "$OWNER_USER" 2>/dev/null || id -gn)"

chown "$OWNER_USER:$OWNER_GROUP" "$CERT_DIR/key.pem" "$CERT_DIR/cert.pem"

# Secure permissions: private key should not be world-readable
chmod 600 "$CERT_DIR/key.pem"
chmod 644 "$CERT_DIR/cert.pem"
