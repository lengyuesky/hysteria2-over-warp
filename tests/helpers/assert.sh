#!/usr/bin/env bash
set -euo pipefail

fail() {
  local message="$1"
  printf 'ASSERTION FAILED: %s\n' "$message" >&2
  exit 1
}

assert_file_exists() {
  local path="$1"
  [[ -e "$path" ]] || fail "expected file to exist: $path"
}

assert_contains() {
  local target="$1"
  local expected="$2"

  assert_file_exists "$target"
  if ! grep -Fq -- "$expected" "$target"; then
    fail "expected $target to contain: $expected"
  fi
}
