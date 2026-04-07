#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tests/helpers/assert.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

stub_bin="$tmpdir/bin"
calls_log="$tmpdir/calls.log"
curl_count_file="$tmpdir/curl.count"

mkdir -p "$stub_bin"

cat > "$stub_bin/warp-svc" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'warp-svc\n' >> "$calls_log"
while true; do
  sleep 30
done
EOF

cat > "$stub_bin/warp-cli" <<EOF
#!/usr/bin/env bash
set -eo pipefail
printf '%s\n' "\$*" >> "$calls_log"
if [ "\$1 \$2" = "registration show" ]; then
  exit 1
fi
exit 0
EOF

cat > "$stub_bin/curl" <<EOF
#!/usr/bin/env bash
set -euo pipefail
count=0
if [ -f "$curl_count_file" ]; then
  count="\$(<"$curl_count_file")"
fi
count=\$((count + 1))
printf '%s' "\$count" > "$curl_count_file"
if [ "\$count" -lt 3 ]; then
  printf 'warp=off\n'
else
  printf 'warp=on\n'
fi
EOF

cat > "$stub_bin/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat > "$stub_bin/mkdir" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'mkdir %s\n' "\$*" >> "$calls_log"
exit 0
EOF

chmod +x "$stub_bin/warp-svc" "$stub_bin/warp-cli" "$stub_bin/curl" "$stub_bin/sleep" "$stub_bin/mkdir"

happy_stdout="$tmpdir/happy.stdout"
happy_stderr="$tmpdir/happy.stderr"
PATH="$stub_bin:$PATH" \
WARP_TRACE_URL="https://example.test/trace" \
WARP_MAX_ATTEMPTS=5 \
WARP_RETRY_SECONDS=0 \
bash "$ROOT/scripts/bootstrap-warp.sh" >"$happy_stdout" 2>"$happy_stderr"

assert_file_exists "$calls_log"
assert_contains "$calls_log" 'mkdir -p /run/cloudflare-warp /var/lib/cloudflare-warp /var/log/cloudflare-warp'
assert_contains "$calls_log" 'warp-svc'
assert_contains "$calls_log" 'status'
assert_contains "$calls_log" 'registration show'
assert_contains "$calls_log" '--accept-tos registration new'
assert_contains "$calls_log" 'connect'
assert_contains "$happy_stdout" 'WARP is connected'

crash_bin="$tmpdir/crash-bin"
mkdir -p "$crash_bin"
cp "$stub_bin/mkdir" "$crash_bin/mkdir"
cp "$stub_bin/sleep" "$crash_bin/sleep"
cat > "$crash_bin/warp-svc" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'warp-svc-crash\n' >> "$calls_log"
printf 'daemon crashed\n' >&2
exit 1
EOF
cat > "$crash_bin/warp-cli" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$crash_bin/warp-svc" "$crash_bin/warp-cli"

crash_stdout="$tmpdir/crash.stdout"
crash_stderr="$tmpdir/crash.stderr"
if PATH="$crash_bin:$PATH" \
  WARP_MAX_ATTEMPTS=2 \
  WARP_RETRY_SECONDS=0 \
  bash "$ROOT/scripts/bootstrap-warp.sh" >"$crash_stdout" 2>"$crash_stderr"; then
  fail 'expected bootstrap-warp to fail when warp-svc exits early'
fi
assert_contains "$crash_stderr" 'WARP daemon exited before becoming ready'
assert_contains "$crash_stderr" 'daemon crashed'

missing_svc_stdout="$tmpdir/missing-svc.stdout"
missing_svc_stderr="$tmpdir/missing-svc.stderr"
missing_svc_bin="$tmpdir/missing-svc-bin"
mkdir -p "$missing_svc_bin"
cp "$stub_bin/warp-cli" "$missing_svc_bin/warp-cli"
if PATH="$missing_svc_bin:$PATH" bash "$ROOT/scripts/bootstrap-warp.sh" >"$missing_svc_stdout" 2>"$missing_svc_stderr"; then
  fail 'expected bootstrap-warp to fail when warp-svc is missing'
fi
assert_contains "$missing_svc_stderr" 'warp-svc not found'

missing_cli_stdout="$tmpdir/missing-cli.stdout"
missing_cli_stderr="$tmpdir/missing-cli.stderr"
missing_cli_bin="$tmpdir/missing-cli-bin"
mkdir -p "$missing_cli_bin"
cp "$stub_bin/mkdir" "$missing_cli_bin/mkdir"
cp "$stub_bin/warp-svc" "$missing_cli_bin/warp-svc"
if PATH="$missing_cli_bin:$PATH" bash "$ROOT/scripts/bootstrap-warp.sh" >"$missing_cli_stdout" 2>"$missing_cli_stderr"; then
  fail 'expected bootstrap-warp to fail when warp-cli is missing'
fi
assert_contains "$missing_cli_stderr" 'warp-cli not found'

fail_bin="$tmpdir/fail-bin"
mkdir -p "$fail_bin"
cp "$stub_bin/mkdir" "$fail_bin/mkdir"
cp "$stub_bin/warp-svc" "$fail_bin/warp-svc"
cp "$stub_bin/warp-cli" "$fail_bin/warp-cli"
cp "$stub_bin/sleep" "$fail_bin/sleep"
cat > "$fail_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'warp=off\n'
EOF
chmod +x "$fail_bin/curl"

fail_stdout="$tmpdir/fail.stdout"
fail_stderr="$tmpdir/fail.stderr"
if PATH="$fail_bin:$PATH" \
  WARP_TRACE_URL="https://example.test/trace" \
  WARP_MAX_ATTEMPTS=2 \
  WARP_RETRY_SECONDS=0 \
  bash "$ROOT/scripts/bootstrap-warp.sh" >"$fail_stdout" 2>"$fail_stderr"; then
  fail 'expected bootstrap-warp to fail when WARP never connects'
fi
assert_contains "$fail_stderr" 'WARP failed to connect after 2 attempts'

delayed_bin="$tmpdir/delayed-bin"
delayed_cli_attempts="$tmpdir/delayed-cli-attempts"
mkdir -p "$delayed_bin"
cp "$stub_bin/mkdir" "$delayed_bin/mkdir"
cp "$stub_bin/warp-svc" "$delayed_bin/warp-svc"
cp "$stub_bin/curl" "$delayed_bin/curl"
cp "$stub_bin/sleep" "$delayed_bin/sleep"
cat > "$delayed_bin/warp-cli" <<EOF
#!/usr/bin/env bash
set -eo pipefail
printf '%s\n' "\$*" >> "$calls_log"
attempt=0
if [ -f "$delayed_cli_attempts" ]; then
  attempt="\$(<"$delayed_cli_attempts")"
fi
attempt=\$((attempt + 1))
printf '%s' "\$attempt" > "$delayed_cli_attempts"
if [ "\$attempt" -le 2 ]; then
  printf 'Unable to connect to the CloudflareWARP daemon: No such file or directory (os error 2)\n\nMaybe the daemon is not running?\n' >&2
  exit 1
fi
if [ "\$1 \$2" = "registration show" ]; then
  exit 1
fi
exit 0
EOF
chmod +x "$delayed_bin/warp-cli"

delayed_stdout="$tmpdir/delayed.stdout"
delayed_stderr="$tmpdir/delayed.stderr"
PATH="$delayed_bin:$PATH" \
WARP_TRACE_URL="https://example.test/trace" \
WARP_MAX_ATTEMPTS=5 \
WARP_RETRY_SECONDS=0 \
bash "$ROOT/scripts/bootstrap-warp.sh" >"$delayed_stdout" 2>"$delayed_stderr"

if [ "$(<"$delayed_cli_attempts")" -le 2 ]; then
  fail 'expected bootstrap-warp to retry until warp-cli can reach the daemon'
fi
assert_contains "$delayed_stdout" 'WARP is connected'
assert_contains "$calls_log" '--accept-tos registration new'
assert_contains "$calls_log" 'connect'

echo "PASS test-bootstrap-warp"
