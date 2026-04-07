#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tests/helpers/assert.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

app_root="$tmpdir/app"
stub_bin="$tmpdir/bin"
output_dir="$tmpdir/output"
calls_log="$tmpdir/calls.log"
cert_dir="$output_dir/certs"
config_path="$output_dir/config/config.yaml"

mkdir -p "$app_root/scripts" "$app_root/config" "$stub_bin" "$output_dir"

cat > "$app_root/scripts/generate-self-signed-cert.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'generate %s %s\n' "\$1" "\$2" >> "$calls_log"
mkdir -p "\$1"
: > "\$1/server.crt"
: > "\$1/server.key"
EOF

cat > "$app_root/scripts/bootstrap-warp.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'bootstrap\n' >> "$calls_log"
EOF

cat > "$app_root/scripts/render-hysteria-config.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'render %s %s\n' "\$1" "\$2" >> "$calls_log"
mkdir -p "\$(dirname "\$2")"
printf 'listen: ":443"\n' > "\$2"
EOF

cat > "$app_root/config/hysteria.yaml.template" <<'EOF'
listen: "__HY2_LISTEN__"
EOF

cat > "$stub_bin/hysteria" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'hysteria %s\n' "\$*" >> "$calls_log"
EOF

chmod +x \
  "$app_root/scripts/generate-self-signed-cert.sh" \
  "$app_root/scripts/bootstrap-warp.sh" \
  "$app_root/scripts/render-hysteria-config.sh" \
  "$stub_bin/hysteria"

happy_stdout="$output_dir/happy.stdout"
happy_stderr="$output_dir/happy.stderr"
APP_ROOT="$app_root" \
PATH="$stub_bin:$PATH" \
HY2_PASSWORD="test-password" \
HY2_DOMAIN="example.test" \
CERT_DIR="$cert_dir" \
HY2_CONFIG_PATH="$config_path" \
bash "$ROOT/entrypoint.sh" >"$happy_stdout" 2>"$happy_stderr"

assert_file_exists "$cert_dir/server.crt"
assert_file_exists "$cert_dir/server.key"
assert_file_exists "$config_path"
assert_file_exists "$calls_log"
assert_contains "$calls_log" "generate $cert_dir example.test"
assert_contains "$calls_log" 'bootstrap'
assert_contains "$calls_log" "render $app_root/config/hysteria.yaml.template $config_path"
assert_contains "$calls_log" "hysteria server -c $config_path"

missing_stdout="$output_dir/missing.stdout"
missing_stderr="$output_dir/missing.stderr"
if APP_ROOT="$app_root" \
  PATH="$stub_bin:$PATH" \
  CERT_DIR="$cert_dir" \
  HY2_CONFIG_PATH="$config_path" \
  bash "$ROOT/entrypoint.sh" >"$missing_stdout" 2>"$missing_stderr"; then
  fail 'expected entrypoint to fail when HY2_PASSWORD is missing'
fi
assert_contains "$missing_stderr" 'HY2_PASSWORD is required'

echo "PASS test-entrypoint"
