#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash "$ROOT_DIR/tests/test-generate-self-signed-cert.sh"
bash "$ROOT_DIR/tests/test-render-hysteria-config.sh"
bash "$ROOT_DIR/tests/test-bootstrap-warp.sh"
bash "$ROOT_DIR/tests/test-entrypoint.sh"
