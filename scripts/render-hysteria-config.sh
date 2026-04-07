#!/usr/bin/env bash
set -euo pipefail

TEMPLATE_PATH="${1:?template path is required}"
OUTPUT_PATH="${2:?output path is required}"

: "${HY2_LISTEN:?HY2_LISTEN is required}"
: "${HY2_PASSWORD:?HY2_PASSWORD is required}"
: "${HY2_CERT_PATH:?HY2_CERT_PATH is required}"
: "${HY2_KEY_PATH:?HY2_KEY_PATH is required}"

escape_sed_replacement() {
  printf '%s' "$1" | sed 's/[\\&|]/\\&/g'
}

mkdir -p "$(dirname "$OUTPUT_PATH")"

sed \
  -e "s|\${HY2_LISTEN}|$(escape_sed_replacement "$HY2_LISTEN")|g" \
  -e "s|\${HY2_PASSWORD}|$(escape_sed_replacement "$HY2_PASSWORD")|g" \
  -e "s|\${HY2_CERT_PATH}|$(escape_sed_replacement "$HY2_CERT_PATH")|g" \
  -e "s|\${HY2_KEY_PATH}|$(escape_sed_replacement "$HY2_KEY_PATH")|g" \
  "$TEMPLATE_PATH" > "$OUTPUT_PATH"
