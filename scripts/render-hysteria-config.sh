#!/usr/bin/env bash
set -euo pipefail

OUTPUT_PATH="${1:?output path is required}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE_PATH="$ROOT_DIR/config/hysteria.yaml.template"

: "${HY2_LISTEN:?HY2_LISTEN is required}"
: "${HY2_PASSWORD:?HY2_PASSWORD is required}"
: "${HY2_CERT_PATH:?HY2_CERT_PATH is required}"
: "${HY2_KEY_PATH:?HY2_KEY_PATH is required}"
: "${HY2_LOG_LEVEL:=info}"

mkdir -p "$(dirname "$OUTPUT_PATH")"
envsubst < "$TEMPLATE_PATH" > "$OUTPUT_PATH"
