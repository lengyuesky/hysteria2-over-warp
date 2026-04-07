#!/usr/bin/env bash
set -euo pipefail

CERT_DIR="${1:?certificate directory is required}"
DOMAIN="${2:?domain is required}"
CERT_PATH="$CERT_DIR/server.crt"
KEY_PATH="$CERT_DIR/server.key"

if [[ -f "$CERT_PATH" && -f "$KEY_PATH" ]]; then
  exit 0
fi

mkdir -p "$CERT_DIR"

openssl req \
  -x509 \
  -nodes \
  -newkey rsa:2048 \
  -keyout "$KEY_PATH" \
  -out "$CERT_PATH" \
  -days 3650 \
  -subj "/CN=$DOMAIN"

chmod 600 "$KEY_PATH"
chmod 644 "$CERT_PATH"
