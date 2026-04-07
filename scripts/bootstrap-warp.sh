#!/usr/bin/env bash
set -euo pipefail

trace_url="${WARP_TRACE_URL:-https://www.cloudflare.com/cdn-cgi/trace}"
max_attempts="${WARP_MAX_ATTEMPTS:-20}"
retry_seconds="${WARP_RETRY_SECONDS:-2}"

command -v warp-svc >/dev/null 2>&1 || {
  echo "warp-svc is required" >&2
  exit 1
}

command -v warp-cli >/dev/null 2>&1 || {
  echo "warp-cli is required" >&2
  exit 1
}

warp-svc >/tmp/warp-svc.log 2>&1 &
svc_pid=$!

cleanup() {
  kill "$svc_pid" 2>/dev/null || true
}

trap cleanup EXIT

if ! warp-cli registration show; then
  warp-cli registration new
fi

warp-cli connect

attempt=1
while [ "$attempt" -le "$max_attempts" ]; do
  if curl -fsSL "$trace_url" | grep -q 'warp=on'; then
    trap - EXIT
    echo "WARP is connected"
    exit 0
  fi

  sleep "$retry_seconds"
  attempt=$((attempt + 1))
done

echo "WARP failed to connect after $max_attempts attempts"
exit 1
