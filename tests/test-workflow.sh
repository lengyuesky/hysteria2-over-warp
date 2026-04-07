#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tests/helpers/assert.sh"

workflow="$ROOT/.github/workflows/docker.yml"

assert_file_exists "$workflow"
assert_contains "$workflow" "pull_request:"
assert_contains "$workflow" "docker/login-action@v3"
assert_contains "$workflow" "docker/build-push-action@v6"
assert_contains "$workflow" "ghcr.io/"

echo "PASS test-workflow"
