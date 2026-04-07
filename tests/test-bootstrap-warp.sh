#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tests/helpers/assert.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

stub_bin="$tmpdir/bin"
calls_log="$tmpdir/calls.log"
curl_count_file="$tmpdir/curl-count"

mkdir -p "$stub_bin"

cat > "$stub_bin/warp-svc" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'warp-svc\n' >> "$CALLS_LOG"
sleep 30
EOF

cat > "$stub_bin/warp-cli" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$CALLS_LOG"
if [ "$*" = "registration show" ]; then
  exit 1
fi
exit 0
EOF

cat > "$stub_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
count=0
if [ -f "$CURL_COUNT_FILE" ]; then
  count="$(<"$CURL_COUNT_FILE")"
fi
count=$((count + 1))
printf '%s' "$count" > "$CURL_COUNT_FILE"
if [ "$count" -lt 3 ]; then
  printf 'warp=off\n'
else
  printf 'warp=on\n'
fi
EOF

cat > "$stub_bin/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

chmod +x "$stub_bin/warp-svc" "$stub_bin/warp-cli" "$stub_bin/curl" "$stub_bin/sleep"

PATH="$stub_bin:$PATH" \
CALLS_LOG="$calls_log" \
CURL_COUNT_FILE="$curl_count_file" \
WARP_TRACE_URL="https://example.test/trace" \
WARP_MAX_ATTEMPTS=5 \
WARP_RETRY_SECONDS=0 \
bash "$ROOT/scripts/bootstrap-warp.sh"

assert_file_exists "$calls_log"
assert_contains "$calls_log" 'warp-svc'
assert_contains "$calls_log" 'registration show'
assert_contains "$calls_log" 'registration new'
assert_contains "$calls_log" 'connect'

echo "PASS test-bootstrap-warp"
