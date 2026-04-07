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

assert_file_contains() {
  local path="$1"
  local expected="$2"

  assert_file_exists "$path"
  if ! grep -Fq "$expected" "$path"; then
    fail "expected file $path to contain: $expected"
  fi
}

assert_equals() {
  local expected="$1"
  local actual="$2"

  if [[ "$expected" != "$actual" ]]; then
    fail "expected [$expected] but got [$actual]"
  fi
}
