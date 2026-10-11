#!/bin/sh
# Development only (develop): makes the RS256 key pair of the security microservice in keys/ (ignored by git)
# and prints the lines to paste into env/dev.env. In qa and main the keys are secrets of the environment, never
# made here. It keeps an existing pair, so running it again changes nothing.
# KEYS_DIR replaces the folder (the checks use it).
set -eu
cd "$(dirname "$0")/.."

dir="${KEYS_DIR:-$(pwd)/keys}"
mkdir -p "$dir"
if [ ! -s "$dir/private.pem" ]; then
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$dir/private.pem"
  openssl pkey -in "$dir/private.pem" -pubout -out "$dir/public.pem"
fi
# The containers run as an unprivileged user that is not the owner of these files: they must be readable.
# That is acceptable for a throw-away development key and is the reason this script refuses to make qa or main keys.
chmod 644 "$dir/private.pem" "$dir/public.pem"

echo "# Paste into env/dev.env (the private key is not printed: it stays in $dir)"
echo "JWT_KEYS_DIR=$dir"
echo "JWT_PUBLIC_KEY_PATH=$dir/public.pem"
printf 'JWT_PUBLIC_KEY='
awk 'BEGIN { ORS = "\\n" } { print }' "$dir/public.pem"
echo
