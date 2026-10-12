#!/bin/sh
# Development only (develop): makes the first Platform Administrator, once, with the command of the security
# service (bootstrap-platform-admin). It does nothing when the platform already has one, so it is safe to repeat.
# Usage: scripts/bootstrap-admin.sh [e-mail]   (or PLATFORM_ADMIN_EMAIL in env/dev.env)
# The password is asked with a hidden prompt, or read from standard input when this is not a terminal. It goes to the
# command through standard input only: never an argument, a variable of the environment or a line of output.
# Needs the stack up (scripts/up.sh dev). ENV_FILE replaces the variables file (the checks use it).
set -eu
cd "$(dirname "$0")/.."

env_file="${ENV_FILE:-env/dev.env}"
if [ ! -f "$env_file" ]; then
  echo "ERROR: $env_file does not exist. Copy env/dev.env.example and start the stack with scripts/up.sh dev first." >&2
  exit 1
fi
case "$env_file" in
  */qa.env|*/main.env|qa.env|main.env) echo "ERROR: development only; in qa and main the administrator comes from the secrets of the environment." >&2; exit 1 ;;
esac
if grep -q 'CHANGE_ME' "$env_file"; then
  echo "ERROR: $env_file still has CHANGE_ME. Fill it and start the stack first." >&2
  exit 1
fi

email="${1:-}"
[ -n "$email" ] || email=$(sed -n 's/^PLATFORM_ADMIN_EMAIL=//p' "$env_file" | tail -n 1 | tr -d '\r')
if [ -z "$email" ]; then
  echo "ERROR: no e-mail. Pass it as an argument or set PLATFORM_ADMIN_EMAIL in $env_file." >&2
  exit 2
fi

case "$env_file" in /*) COMPOSE_ENV_FILE="$env_file" ;; *) COMPOSE_ENV_FILE="$(pwd)/$env_file" ;; esac
export COMPOSE_ENV_FILE
dc() { docker compose -f platform.yml --env-file "$env_file" "$@"; }

if ! dc ps --status running --services </dev/null 2>/dev/null | grep -qx postgres; then
  echo "ERROR: the stack is not running. Start it with scripts/up.sh dev --demo." >&2
  exit 1
fi

if [ -t 0 ]; then
  trap 'stty echo' EXIT
  trap 'exit 130' INT TERM
  printf 'Temporary password for %s: ' "$email" >&2
  stty -echo
  IFS= read -r password
  stty echo
  echo >&2
else
  IFS= read -r password || true
fi
if [ -z "$password" ]; then
  echo "ERROR: the password is empty." >&2
  exit 2
fi

# printf is a shell builtin, so the password is not in the arguments of any process
printf '%s\n' "$password" | dc run --rm -T -e "PLATFORM_ADMIN_EMAIL=$email" security bootstrap-platform-admin
