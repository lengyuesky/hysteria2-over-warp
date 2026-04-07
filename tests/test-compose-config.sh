#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tests/helpers/assert.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
output="$tmpdir/compose.yaml"

docker compose --env-file "$ROOT/.env.example" -f "$ROOT/docker-compose.yml" config > "$output"

assert_contains "$output" "NET_ADMIN"
assert_contains "$output" "/dev/net/tun:/dev/net/tun"
assert_contains "$output" "443/udp"
assert_contains "$output" "/var/lib/hysteria"

echo "PASS test-compose-config"
