#!/bin/bash
set -euo pipefail

# Get the project root directory (one level up from scripts)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Function to validate IP address format
validate_ip() {
    local ip=$1
    if [[ ! $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 1
    fi
    local IFS='.'
    read -r a b c d <<<"$ip"
    ((a <= 255 && b <= 255 && c <= 255 && d <= 255))
}

# Escape replacement string for sed (handles \, &, and delimiter |)
escape_sed_replacement() {
    printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

# Run sed in-place in a way that works on macOS (BSD sed) and GNU sed
sed_in_place() {
    local expr=$1
    local file=$2

    if sed --version >/dev/null 2>&1; then
        # GNU sed (Linux, many Windows ports)
        sed -i "$expr" "$file"
    else
        # BSD sed (macOS)
        sed -i '' "$expr" "$file"
    fi
}

# Replace a whole line matching a pattern, whatever its current value, and verify the result
update_line() {
    local file=$1
    local pattern=$2
    local new_line=$3

    if [ ! -f "$file" ]; then
        echo "Error: Required file not found: $file"
        exit 1
    fi

    local escaped_new
    escaped_new="$(escape_sed_replacement "$new_line")"

    if ! sed_in_place "s|$pattern|$escaped_new|" "$file" || ! grep -Fqx "$new_line" "$file"; then
        echo "Error: Failed to update $file"
        exit 1
    fi

    echo "Updated $file"
}

# Bootstrap .env.development from the example template if missing.
# .env.development is gitignored, so a fresh checkout won't have it.
ENV_FILE="$PROJECT_ROOT/.env.development"
ENV_EXAMPLE="$PROJECT_ROOT/.env.development.example"
if [ ! -f "$ENV_FILE" ]; then
    if [ ! -f "$ENV_EXAMPLE" ]; then
        echo "Error: $ENV_EXAMPLE not found"
        exit 1
    fi
    cp "$ENV_EXAMPLE" "$ENV_FILE"
    echo "Created $ENV_FILE from $ENV_EXAMPLE"
fi

# Get local IP address
echo "Please enter your local IP address (e.g., 192.168.1.100):"
read -r local_ip

# Validate IP address
while ! validate_ip "$local_ip"; do
    echo "Invalid IP address format. Please enter a valid IP address:"
    read -r local_ip
done

# Update .env.development
update_line "$ENV_FILE" '^SERVER_NAME=.*$' "SERVER_NAME=$local_ip"
update_line "$ENV_FILE" '^HOST=.*$' 'HOST=0.0.0.0'

# Update client environments
escaped_ip="$(escape_sed_replacement "$local_ip")"

# Use regex to match any current IP so the script is idempotent across runs
sed_in_place "s|apiUrl: '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*:9000'|apiUrl: '$escaped_ip:9000'|g" \
    "$PROJECT_ROOT/client/web/src/environments/environment.ts"
sed_in_place "s|webUrl: '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*'|webUrl: '$escaped_ip'|g" \
    "$PROJECT_ROOT/client/web/src/environments/environment.ts"
echo "Updated environment.ts"

sed_in_place "s|apiUrl: '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*'|apiUrl: '$escaped_ip'|g" \
    "$PROJECT_ROOT/client/web/src/environments/environment.docker-dev.ts"
sed_in_place "s|webUrl: '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*'|webUrl: '$escaped_ip'|g" \
    "$PROJECT_ROOT/client/web/src/environments/environment.docker-dev.ts"
echo "Updated environment.docker-dev.ts"

sed_in_place "s|static let host = \"[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\"|static let host = \"$escaped_ip\"|g" \
    "$PROJECT_ROOT/client/ios/PastePoint/Core/Config/AppEnvironment.swift"
echo "Updated AppEnvironment.swift"

# Update server configurations; the server rejects WebSocket origins other than this one
for config in development docker-dev; do
    update_line "$PROJECT_ROOT/server/config/$config.toml" \
        '^cors_allowed_origins = "https://[0-9.][0-9.]*"$' "cors_allowed_origins = \"https://$local_ip\""

    # Keep the web client's update-policy URL in sync with the host
    update_line "$PROJECT_ROOT/server/config/$config.toml" \
        '^url = "https://[0-9.][0-9.]*"$' "url = \"https://$local_ip\""
done

echo "Network configuration completed successfully!"
echo "Your local IP address ($local_ip) has been set in all configuration files."
echo "Generate a matching certificate with './scripts/generate-certs.sh $local_ip', then run 'make dev'."
