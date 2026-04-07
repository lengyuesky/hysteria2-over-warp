#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_file_exists() {
  [ -f "$1" ] || fail "expected file $1 to exist"
}

assert_contains() {
  grep -Fq "$2" "$1" || fail "expected '$2' in $1"
}
