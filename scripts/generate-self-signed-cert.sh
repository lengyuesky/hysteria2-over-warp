#!/usr/bin/env bash
set -euo pipefail

CERT_PATH="${1:?certificate path is required}"
KEY_PATH="${2:?key path is required}"
DOMAIN="${3:-localhost}"

mkdir -p "$(dirname "$CERT_PATH")" "$(dirname "$KEY_PATH")"

openssl req \
  -x509 \
  -nodes \
  -newkey rsa:2048 \
  -keyout "$KEY_PATH" \
  -out "$CERT_PATH" \
  -days 365 \
  -subj "/CN=$DOMAIN" \
  -addext "subjectAltName=DNS:$DOMAIN"
