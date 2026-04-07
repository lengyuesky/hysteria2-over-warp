#!/usr/bin/env bash
set -euo pipefail

cert_dir="${1:?usage: generate-self-signed-cert.sh <cert-dir> <domain>}"
domain="${2:-localhost}"

mkdir -p "$cert_dir"

cert_path="$cert_dir/server.crt"
key_path="$cert_dir/server.key"

if [ -s "$cert_path" ] && [ -s "$key_path" ]; then
  echo "Using existing certificate files in $cert_dir"
  exit 0
fi

openssl req \
  -x509 \
  -nodes \
  -newkey rsa:2048 \
  -keyout "$key_path" \
  -out "$cert_path" \
  -days 3650 \
  -subj "/CN=$domain"

chmod 600 "$key_path"
chmod 644 "$cert_path"
