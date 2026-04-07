#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

docker build -t hysteria2-over-warp:test "$ROOT" >/tmp/hysteria2-over-warp-build.log

docker run --rm --entrypoint /bin/sh hysteria2-over-warp:test -c '
  command -v warp-cli >/dev/null 2>&1 &&
  command -v warp-svc >/dev/null 2>&1 &&
  command -v hysteria >/dev/null 2>&1 &&
  test -x /app/entrypoint.sh &&
  test -x /app/scripts/bootstrap-warp.sh &&
  test -f /app/config/hysteria.yaml.template
'

echo "PASS test-image-smoke"
