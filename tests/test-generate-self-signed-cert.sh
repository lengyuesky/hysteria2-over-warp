#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/helpers/assert.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CERT_DIR="$TMP_DIR/certs"
SCRIPT_PATH="$ROOT_DIR/scripts/generate-self-signed-cert.sh"

bash "$SCRIPT_PATH" "$CERT_DIR" "test.example"

assert_file_exists "$CERT_DIR/server.crt"
assert_file_exists "$CERT_DIR/server.key"
assert_contains "$CERT_DIR/server.crt" "BEGIN CERTIFICATE"
assert_contains "$CERT_DIR/server.key" "BEGIN PRIVATE KEY"
assert_contains <(openssl x509 -in "$CERT_DIR/server.crt" -noout -subject) "subject=CN = test.example"
assert_contains <(stat -c '%a' "$CERT_DIR/server.crt") "644"
assert_contains <(stat -c '%a' "$CERT_DIR/server.key") "600"

if ! openssl x509 -in "$CERT_DIR/server.crt" -noout -checkend $((3649 * 24 * 60 * 60)) >/dev/null; then
  fail "expected certificate to be valid for at least 3649 days"
fi

if openssl x509 -in "$CERT_DIR/server.crt" -noout -checkend $((3650 * 24 * 60 * 60)) >/dev/null; then
  fail "expected certificate validity to be limited to about 3650 days"
fi

printf 'existing cert\n' > "$CERT_DIR/server.crt"
printf 'existing key\n' > "$CERT_DIR/server.key"
bash "$SCRIPT_PATH" "$CERT_DIR" "ignored.example"
assert_contains "$CERT_DIR/server.crt" "existing cert"
assert_contains "$CERT_DIR/server.key" "existing key"
