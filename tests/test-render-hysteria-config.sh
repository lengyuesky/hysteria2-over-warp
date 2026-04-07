#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tests/helpers/assert.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

HY2_LISTEN=":8443" \
HY2_PASSWORD="test-password" \
HY2_CERT_PATH="/certs/server.crt" \
HY2_KEY_PATH="/certs/server.key" \
bash "$ROOT/scripts/render-hysteria-config.sh" \
  "$ROOT/config/hysteria.yaml.template" \
  "$tmpdir/config.yaml"

assert_file_exists "$tmpdir/config.yaml"
assert_contains "$tmpdir/config.yaml" 'listen: ":8443"'
assert_contains "$tmpdir/config.yaml" 'cert: "/certs/server.crt"'
assert_contains "$tmpdir/config.yaml" 'key: "/certs/server.key"'
assert_contains "$tmpdir/config.yaml" 'password: "test-password"'

echo "PASS test-render-hysteria-config"
