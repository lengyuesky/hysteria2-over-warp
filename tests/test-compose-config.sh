#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tests/helpers/assert.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
output="$tmpdir/compose.yaml"

docker compose --env-file "$ROOT/.env.example" -f "$ROOT/docker-compose.yml" config > "$output"

assert_contains "$output" "NET_ADMIN"
assert_contains "$output" "devices:"
assert_contains "$output" "/dev/net/tun"
assert_contains "$output" "published: \"443\""
assert_contains "$output" "target: 443"
assert_contains "$output" "protocol: udp"
assert_contains "$output" "/var/lib/hysteria"
assert_contains "$output" "enable_ipv6: true"
assert_contains "$output" "172.31.0.0/24"
assert_contains "$output" "fd00:172:31::/64"

echo "PASS test-compose-config"
