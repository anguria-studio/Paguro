#!/bin/sh
set -eu

REPOSITORY_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TLS_DIR=$(mktemp -d "${TMPDIR:-/tmp}/atoll-compatibility.XXXXXX")

cleanup() {
    rm -rf -- "$TLS_DIR"
}
trap cleanup EXIT INT TERM

if ! command -v python3 >/dev/null 2>&1; then
    echo "Python 3 is required to run the compatibility fixture." >&2
    exit 1
fi
if ! command -v openssl >/dev/null 2>&1; then
    echo "OpenSSL is required to create the temporary fixture certificate." >&2
    exit 1
fi

openssl req \
    -x509 \
    -newkey rsa:2048 \
    -sha256 \
    -nodes \
    -days 1 \
    -keyout "$TLS_DIR/localhost-key.pem" \
    -out "$TLS_DIR/localhost-cert.pem" \
    -config "$REPOSITORY_DIR/fixtures/compatibility/openssl.cnf" \
    >/dev/null 2>&1

chmod 600 "$TLS_DIR/localhost-key.pem"

python3 "$REPOSITORY_DIR/fixtures/compatibility/server.py" \
    --certificate "$TLS_DIR/localhost-cert.pem" \
    --key "$TLS_DIR/localhost-key.pem"
