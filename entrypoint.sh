#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="${APP_ROOT:-/app}"
SCRIPT_DIR="$APP_ROOT/scripts"
TEMPLATE_PATH="$APP_ROOT/config/hysteria.yaml.template"
CERT_DIR="${CERT_DIR:-/var/lib/hysteria/certs}"
HY2_CONFIG_PATH="${HY2_CONFIG_PATH:-/etc/hysteria/config.yaml}"
HY2_LISTEN="${HY2_LISTEN:-:443}"
HY2_DOMAIN="${HY2_DOMAIN:-localhost}"
HY2_CERT_PATH="${HY2_CERT_PATH:-$CERT_DIR/server.crt}"
HY2_KEY_PATH="${HY2_KEY_PATH:-$CERT_DIR/server.key}"

: "${HY2_PASSWORD:?HY2_PASSWORD is required}"

mkdir -p "$CERT_DIR" "$(dirname "$HY2_CONFIG_PATH")"

if [ ! -f "$HY2_CERT_PATH" ] || [ ! -f "$HY2_KEY_PATH" ]; then
  bash "$SCRIPT_DIR/generate-self-signed-cert.sh" "$CERT_DIR" "$HY2_DOMAIN"
  HY2_CERT_PATH="$CERT_DIR/server.crt"
  HY2_KEY_PATH="$CERT_DIR/server.key"
fi

export HY2_LISTEN HY2_PASSWORD HY2_CERT_PATH HY2_KEY_PATH

bash "$SCRIPT_DIR/bootstrap-warp.sh"
bash "$SCRIPT_DIR/render-hysteria-config.sh" "$TEMPLATE_PATH" "$HY2_CONFIG_PATH"

exec hysteria server -c "$HY2_CONFIG_PATH"
