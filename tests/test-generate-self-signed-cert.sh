#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tests/helpers/assert.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

bash "$ROOT/scripts/generate-self-signed-cert.sh" "$tmpdir/certs" "test.example"

assert_file_exists "$tmpdir/certs/server.crt"
assert_file_exists "$tmpdir/certs/server.key"
openssl x509 -in "$tmpdir/certs/server.crt" -noout >/dev/null
openssl pkey -in "$tmpdir/certs/server.key" -noout >/dev/null

echo "PASS test-generate-self-signed-cert"
