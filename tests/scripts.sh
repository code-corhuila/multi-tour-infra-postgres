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

# A fake docker on the PATH: "ps" lists postgres when FAKE_UP=1; any other call records its arguments and its input
mkdir -p "$TMP/bin"
cat > "$TMP/bin/docker" <<'FAKE'
#!/bin/sh
case "$*" in
  *" ps "*) [ "${FAKE_UP:-1}" = 1 ] && echo postgres; exit 0 ;;
esac
printf '%s\n' "$@" > "$FAKE_ARGS"
cat > "$FAKE_STDIN"
FAKE
chmod +x "$TMP/bin/docker"
printf 'PG_DATABASE=multitour\n' > "$TMP/ok.env"
printf 'SERVICE_TOKEN=CHANGE_ME\n' > "$TMP/placeholder.env"

boot() { # args of the script; the password comes from stdin
  PATH="$TMP/bin:$PATH" ENV_FILE="${BOOT_ENV:-$TMP/ok.env}" FAKE_ARGS="$TMP/args.txt" FAKE_STDIN="$TMP/stdin.txt" sh scripts/bootstrap-admin.sh "$@"
}

bootstrap_refuses_without_an_email() {
  out=$(echo 's3cret-Pass' | boot 2>&1) && return 1
  echo "$out" | grep -qi 'e-mail' && ! echo "$out" | grep -q 's3cret-Pass'
}

bootstrap_refuses_while_the_env_has_change_me() {
  out=$(echo 's3cret-Pass' | BOOT_ENV="$TMP/placeholder.env" boot admin@example.com 2>&1) && return 1
  echo "$out" | grep -q 'CHANGE_ME'
}

bootstrap_refuses_when_the_stack_is_not_up() {
  out=$(echo 's3cret-Pass' | FAKE_UP=0 boot admin@example.com 2>&1) && return 1
  echo "$out" | grep -qi 'not running'
}

bootstrap_refuses_qa_and_main_files() {
  mkdir -p "$TMP/e" && cp "$TMP/ok.env" "$TMP/e/qa.env"
  out=$(echo 's3cret-Pass' | BOOT_ENV="$TMP/e/qa.env" boot admin@example.com 2>&1) && return 1
  echo "$out" | grep -qi 'development only'
}

bootstrap_passes_the_password_only_through_stdin() {
  out=$(echo 's3cret-Pass' | boot admin@example.com 2>&1) || return 1
  [ "$(head -n 1 "$TMP/stdin.txt")" = "s3cret-Pass" ] || return 1
  grep -q 'bootstrap-platform-admin' "$TMP/args.txt" && grep -q 'PLATFORM_ADMIN_EMAIL=admin@example.com' "$TMP/args.txt" || return 1
  ! grep -q 's3cret-Pass' "$TMP/args.txt" && ! echo "$out" | grep -q 's3cret-Pass'
}

scripts_are_valid_shell() {
  for s in scripts/dev-keys.sh scripts/dev-token.sh scripts/build-portal.sh scripts/bootstrap-admin.sh; do sh -n "$s" || return 1; done
}

check "scripts_are_valid_shell" scripts_are_valid_shell
check "keys_are_made_once_and_are_a_rs256_pair" keys_are_made_once_and_are_a_rs256_pair
check "keys_script_prints_the_variables_to_paste" keys_script_prints_the_variables_to_paste
check "token_script_refuses_a_missing_name" token_script_refuses_a_missing_name
check "portal_script_refuses_a_missing_folder" portal_script_refuses_a_missing_folder
check "bootstrap_refuses_without_an_email" bootstrap_refuses_without_an_email
check "bootstrap_refuses_while_the_env_has_change_me" bootstrap_refuses_while_the_env_has_change_me
check "bootstrap_refuses_when_the_stack_is_not_up" bootstrap_refuses_when_the_stack_is_not_up
check "bootstrap_refuses_qa_and_main_files" bootstrap_refuses_qa_and_main_files
check "bootstrap_passes_the_password_only_through_stdin" bootstrap_passes_the_password_only_through_stdin
[ "$fail" = 0 ] && echo "ALL CHECKS PASSED" || echo "SOME CHECKS FAILED"
exit "$fail"
