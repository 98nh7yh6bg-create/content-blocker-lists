#!/bin/bash
# Signs a file with the Ed25519 key in $SIGNING_KEY (base64 raw private key,
# the 32-byte seed) and prints the base64 signature. The app checks it with
# the public key. OpenSSL 3, so it runs on Linux runners as well as Macs.
set -euo pipefail
[ $# -eq 1 ] || { echo "usage: sign.sh <file>" >&2; exit 2; }
[ -n "${SIGNING_KEY:-}" ] || { echo "SIGNING_KEY is missing" >&2; exit 1; }
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
chmod 700 "$dir"
# A PKCS#8 wrapper around the seed: OpenSSL reads Ed25519 keys only that way.
{ printf '\x30\x2e\x02\x01\x00\x30\x05\x06\x03\x2b\x65\x70\x04\x22\x04\x20'; printf '%s' "$SIGNING_KEY" | tr -d ' \n\r' | openssl base64 -d -A; } > "$dir/key.der"
[ "$(wc -c < "$dir/key.der" | tr -d ' ')" = 48 ] || { echo "SIGNING_KEY is not a 32-byte key" >&2; exit 1; }
openssl pkeyutl -sign -rawin -keyform DER -inkey "$dir/key.der" -in "$1" | openssl base64 -A
echo
