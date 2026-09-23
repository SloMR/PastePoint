#!/usr/bin/env sh
set -e

# Substitute environment variables in the nginx config template
envsubst "\$SERVER_NAME \$SSL_CERT_PATH \$SSL_CERT_KEY_PATH" </etc/nginx/templates/default.conf.template >/etc/nginx/conf.d/default.conf
echo "Starting Nginx..."

# Execute the main command
exec "$@"
