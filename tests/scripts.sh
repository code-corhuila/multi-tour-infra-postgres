#!/bin/sh
# Checks of the development helper scripts. They need no Docker: only sh and openssl.
set -u
cd "$(dirname "$0")/.." || exit 1
fail=0
check() { # name, function
  if "$2" >/dev/null 2>&1; then echo "PASS  $1"; else echo "FAIL  $1"; fail=1; fi
}

TMP=$(mktemp -d)
trap 'rmdir_all' EXIT
rmdir_all() { find "$TMP" -depth -delete; }

keys_are_made_once_and_are_a_rs256_pair() {
  KEYS_DIR="$TMP/keys" sh scripts/dev-keys.sh >"$TMP/out.txt" || return 1
  [ -s "$TMP/keys/private.pem" ] && [ -s "$TMP/keys/public.pem" ] || return 1
  openssl pkey -in "$TMP/keys/private.pem" -noout || return 1
  first=$(cksum < "$TMP/keys/private.pem")
  KEYS_DIR="$TMP/keys" sh scripts/dev-keys.sh >/dev/null || return 1
  [ "$first" = "$(cksum < "$TMP/keys/private.pem")" ]
}

keys_script_prints_the_variables_to_paste() {
  grep -q '^JWT_KEYS_DIR=' "$TMP/out.txt" && grep -q '^JWT_PUBLIC_KEY=' "$TMP/out.txt" && ! grep -q 'PRIVATE' "$TMP/out.txt"
}

token_script_refuses_a_missing_name() { ! sh scripts/dev-token.sh; }

portal_script_refuses_a_missing_folder() { ! PORTAL_DIR="$TMP/none" FRONT_DIR="$TMP/none" sh scripts/build-portal.sh; }

scripts_are_valid_shell() {
  for s in scripts/dev-keys.sh scripts/dev-token.sh scripts/build-portal.sh; do sh -n "$s" || return 1; done
}

check "scripts_are_valid_shell" scripts_are_valid_shell
check "keys_are_made_once_and_are_a_rs256_pair" keys_are_made_once_and_are_a_rs256_pair
check "keys_script_prints_the_variables_to_paste" keys_script_prints_the_variables_to_paste
check "token_script_refuses_a_missing_name" token_script_refuses_a_missing_name
check "portal_script_refuses_a_missing_folder" portal_script_refuses_a_missing_folder
[ "$fail" = 0 ] && echo "ALL CHECKS PASSED" || echo "SOME CHECKS FAILED"
exit "$fail"
