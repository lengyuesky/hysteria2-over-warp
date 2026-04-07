#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/helpers/assert.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CERT_PATH="$TMP_DIR/server.crt"
KEY_PATH="$TMP_DIR/server.key"
DOMAIN="example.com"
SCRIPT_PATH="$ROOT_DIR/scripts/generate-self-signed-cert.sh"

bash "$SCRIPT_PATH" "$CERT_PATH" "$KEY_PATH" "$DOMAIN"

assert_file_exists "$CERT_PATH"
assert_file_exists "$KEY_PATH"

SUBJECT="$(openssl x509 -in "$CERT_PATH" -noout -subject)"
assert_file_contains "$CERT_PATH" "BEGIN CERTIFICATE"
assert_file_contains "$KEY_PATH" "BEGIN PRIVATE KEY"
assert_file_contains <(openssl x509 -in "$CERT_PATH" -text -noout) "DNS:$DOMAIN"
assert_equals "subject=CN = $DOMAIN" "$SUBJECT"
