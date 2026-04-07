#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/helpers/assert.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

OUTPUT_PATH="$TMP_DIR/hysteria.yaml"
TEMPLATE_PATH="$ROOT_DIR/config/hysteria.yaml.template"
SCRIPT_PATH="$ROOT_DIR/scripts/render-hysteria-config.sh"

HY2_LISTEN=":8443" \
HY2_PASSWORD="test-password" \
HY2_CERT_PATH="/certs/server.crt" \
HY2_KEY_PATH="/certs/server.key" \
bash "$SCRIPT_PATH" "$TEMPLATE_PATH" "$OUTPUT_PATH"

assert_file_exists "$OUTPUT_PATH"
assert_contains "$OUTPUT_PATH" "listen: \":8443\""
assert_contains "$OUTPUT_PATH" "cert: \"/certs/server.crt\""
assert_contains "$OUTPUT_PATH" "key: \"/certs/server.key\""
assert_contains "$OUTPUT_PATH" "password: \"test-password\""
