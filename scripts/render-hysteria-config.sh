#!/usr/bin/env bash
set -euo pipefail

template_path="${1:?usage: render-hysteria-config.sh <template> <output>}"
output_path="${2:?usage: render-hysteria-config.sh <template> <output>}"

: "${HY2_LISTEN:?HY2_LISTEN is required}"
: "${HY2_PASSWORD:?HY2_PASSWORD is required}"
: "${HY2_CERT_PATH:?HY2_CERT_PATH is required}"
: "${HY2_KEY_PATH:?HY2_KEY_PATH is required}"

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\\/&|]/\\&/g'
}

mkdir -p "$(dirname "$output_path")"

sed \
  -e "s|__HY2_LISTEN__|$(escape_sed_replacement "$HY2_LISTEN")|g" \
  -e "s|__HY2_CERT_PATH__|$(escape_sed_replacement "$HY2_CERT_PATH")|g" \
  -e "s|__HY2_KEY_PATH__|$(escape_sed_replacement "$HY2_KEY_PATH")|g" \
  -e "s|__HY2_PASSWORD__|$(escape_sed_replacement "$HY2_PASSWORD")|g" \
  "$template_path" > "$output_path"
