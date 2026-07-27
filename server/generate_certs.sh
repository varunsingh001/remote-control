#!/bin/bash
set -e

CERT_DIR="$(dirname "$0")/certs"
mkdir -p "$CERT_DIR"

if [ -f "$CERT_DIR/server.key" ] && [ -f "$CERT_DIR/server.crt" ]; then
    echo "Certs already exist in $CERT_DIR — delete them first to regenerate."
    exit 0
fi

openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$CERT_DIR/server.key" \
    -out "$CERT_DIR/server.crt" \
    -days 3650 \
    -subj "/CN=Remote Control"

echo "Generated self-signed cert and key in $CERT_DIR"
