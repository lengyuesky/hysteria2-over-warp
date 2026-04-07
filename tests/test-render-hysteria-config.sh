#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/helpers/assert.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

OUTPUT_PATH="$TMP_DIR/hysteria.yaml"
CERT_PATH="$TMP_DIR/server.crt"
KEY_PATH="$TMP_DIR/server.key"
SCRIPT_PATH="$ROOT_DIR/scripts/render-hysteria-config.sh"

cat > "$CERT_PATH" <<'EOF'
cert-placeholder
EOF

cat > "$KEY_PATH" <<'EOF'
key-placeholder
EOF

HY2_LISTEN=":8443" \
HY2_PASSWORD="super-secret" \
HY2_CERT_PATH="$CERT_PATH" \
HY2_KEY_PATH="$KEY_PATH" \
HY2_LOG_LEVEL="debug" \
bash "$SCRIPT_PATH" "$OUTPUT_PATH"

assert_file_exists "$OUTPUT_PATH"
assert_file_contains "$OUTPUT_PATH" "listen: :8443"
assert_file_contains "$OUTPUT_PATH" "password: super-secret"
assert_file_contains "$OUTPUT_PATH" "cert: $CERT_PATH"
assert_file_contains "$OUTPUT_PATH" "key: $KEY_PATH"
assert_file_contains "$OUTPUT_PATH" "level: debug"
