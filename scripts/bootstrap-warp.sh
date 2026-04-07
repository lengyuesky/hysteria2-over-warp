#!/usr/bin/env bash
set -euo pipefail

trace_url="${WARP_TRACE_URL:-https://www.cloudflare.com/cdn-cgi/trace}"
max_attempts="${WARP_MAX_ATTEMPTS:-20}"
retry_seconds="${WARP_RETRY_SECONDS:-2}"

command -v warp-svc >/dev/null 2>&1 || {
  echo "warp-svc not found" >&2
  exit 1
}

command -v warp-cli >/dev/null 2>&1 || {
  echo "warp-cli not found" >&2
  exit 1
}

runtime_dir="${WARP_RUNTIME_DIR:-/run/cloudflare-warp}"
state_dir="${WARP_STATE_DIR:-/var/lib/cloudflare-warp}"
log_dir="${WARP_LOG_DIR:-/var/log/cloudflare-warp}"
warp_socket_path="${WARP_SOCKET_PATH:-$runtime_dir/warp_service}"

mkdir -p "$runtime_dir" "$state_dir" "$log_dir"
rm -f "$warp_socket_path"

warp_log_path="/tmp/warp-svc.log"
warp-svc >"$warp_log_path" 2>&1 &
svc_pid=$!

cleanup() {
  if kill -0 "$svc_pid" 2>/dev/null; then
    kill "$svc_pid" 2>/dev/null || true
  fi
}

trap cleanup EXIT

attempt=1
while [ "$attempt" -le "$max_attempts" ]; do
  if ! kill -0 "$svc_pid" 2>/dev/null; then
    echo "WARP daemon exited before becoming ready" >&2
    if [ -f "$warp_log_path" ]; then
      cat "$warp_log_path" >&2
    fi
    exit 1
  fi

  if [ -S "$warp_socket_path" ] || [ -e "$warp_socket_path" ]; then
    break
  fi

  sleep "$retry_seconds"
  attempt=$((attempt + 1))
done

if [ "$attempt" -gt "$max_attempts" ]; then
  echo "WARP daemon failed to start after $max_attempts attempts" >&2
  if [ -f "$warp_log_path" ]; then
    cat "$warp_log_path" >&2
  fi
  exit 1
fi

if ! warp-cli registration show >/dev/null 2>&1; then
  warp-cli registration delete >/dev/null 2>&1 || true
  warp-cli --accept-tos registration new
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

echo "WARP failed to connect after $max_attempts attempts" >&2
exit 1
