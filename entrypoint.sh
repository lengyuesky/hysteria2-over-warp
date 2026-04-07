#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="${APP_ROOT:-/app}"
SCRIPT_DIR="$APP_ROOT/scripts"
TEMPLATE_PATH="$APP_ROOT/config/hysteria.yaml.template"
CERT_DIR="${CERT_DIR:-/var/lib/hysteria/certs}"
HY2_CONFIG_PATH="${HY2_CONFIG_PATH:-/etc/hysteria/config.yaml}"
HY2_LISTEN="${HY2_LISTEN:-:443}"
HY2_DOMAIN="${HY2_DOMAIN:-localhost}"
HY2_PORT="${HY2_PORT:-443}"
HY2_CERT_PATH="${HY2_CERT_PATH:-$CERT_DIR/server.crt}"
HY2_KEY_PATH="${HY2_KEY_PATH:-$CERT_DIR/server.key}"
use_insecure_share_link=0

: "${HY2_PASSWORD:?HY2_PASSWORD is required}"

mkdir -p "$CERT_DIR" "$(dirname "$HY2_CONFIG_PATH")"

if [ ! -s "$HY2_CERT_PATH" ] || [ ! -s "$HY2_KEY_PATH" ]; then
  bash "$SCRIPT_DIR/generate-self-signed-cert.sh" "$CERT_DIR" "$HY2_DOMAIN"
  HY2_CERT_PATH="$CERT_DIR/server.crt"
  HY2_KEY_PATH="$CERT_DIR/server.key"
  use_insecure_share_link=1
fi

export HY2_LISTEN HY2_PASSWORD HY2_CERT_PATH HY2_KEY_PATH

bash "$SCRIPT_DIR/bootstrap-warp.sh"
bash "$SCRIPT_DIR/render-hysteria-config.sh" "$TEMPLATE_PATH" "$HY2_CONFIG_PATH"

share_link="hy2://${HY2_PASSWORD}@${HY2_DOMAIN}:${HY2_PORT}/?sni=${HY2_DOMAIN}"
if [ "$use_insecure_share_link" -eq 1 ]; then
  share_link="${share_link}&insecure=1"
fi

echo "HY2 share link:"
echo "$share_link"

exec hysteria server -c "$HY2_CONFIG_PATH"
