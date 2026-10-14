#!/bin/sh
# Brings up the platform of one environment through platform.yml and waits until it is healthy.
# Usage: scripts/up.sh dev|qa|main [--check] [--demo]
#   --check  only verifies the sibling repositories and that the composition resolves; starts nothing
#   --demo   also publishes the front on port 4200 (demo-front-port.yml), for a browser on this machine
# Order: the instances (PostgreSQL, MongoDB), then the migration runners, then the services.
# The repositories it includes must sit beside this one. ENV_FILE and SIBLINGS_DIR replace the variables file
# and the folder that holds the siblings (the checks use them; a person rarely needs to).
set -eu
cd "$(dirname "$0")/.."

usage() { echo "usage: scripts/up.sh dev|qa|main [--check] [--demo]" >&2; exit 2; }
env_name="${1:-}"
case "$env_name" in
  dev|qa|main) ;;
  *) usage ;;
esac
shift
check=0
files="-f platform.yml"
for arg in "$@"; do
  case "$arg" in
    --check) check=1 ;;
    --demo) files="-f platform.yml -f demo-front-port.yml" ;;
    *) usage ;;
  esac
done

env_file="${ENV_FILE:-env/$env_name.env}"
if [ ! -f "$env_file" ]; then
  echo "ERROR: $env_file does not exist. Copy env/$env_name.env.example to $env_file and fill the secrets." >&2
  exit 1
fi

# A repository that platform.yml includes and that is not beside this one stops the start, with its name
siblings="${SIBLINGS_DIR:-..}"
missing=0
for repo in multi-tour-infra-mongo multi-tour-identity-audit-api multi-tour-identity-audit-db multi-tour-security multi-tour-workflow-onboard-tenant multi-tour-worker-event-relay multi-tour-api-gateway multi-tour-front multi-tour-identity-audit-portal multi-tour-commercial-reservation-portal; do
  if [ ! -d "$siblings/$repo" ]; then
    echo "ERROR: $repo is missing in $siblings. Clone it: git clone https://github.com/code-corhuila/$repo.git $siblings/$repo" >&2
    missing=1
  fi
done
[ "$missing" = 0 ] || exit 1

# Every include of platform.yml reads this file (an included project does not see --env-file by itself)
case "$env_file" in /*) COMPOSE_ENV_FILE="$env_file" ;; *) COMPOSE_ENV_FILE="$(pwd)/$env_file" ;; esac
export COMPOSE_ENV_FILE

# shellcheck disable=SC2086 # $files is a fixed list of two options
dc() { docker compose $files --env-file "$env_file" "$@"; }

if [ "$check" = 1 ]; then
  dc --profile tooling config >/dev/null
  exit 0
fi

# An example left as it is would start services with placeholder secrets
if grep -q 'CHANGE_ME' "$env_file"; then
  echo "ERROR: $env_file still has CHANGE_ME. Fill it (scripts/dev-keys.sh and scripts/dev-token.sh help in develop)." >&2
  exit 1
fi

# Without the portal module the image builds and the area answers "not available" in the browser
[ -f "$siblings/multi-tour-front/portals/identity-audit-portal.js" ] || echo "WARNING: $siblings/multi-tour-front/portals/identity-audit-portal.js is missing; run scripts/build-portal.sh first" >&2

# The other repositories join this network by name, so it cannot belong to this compose file (D-05)
docker network inspect platform >/dev/null 2>&1 || docker network create platform >/dev/null

dc up -d --wait postgres mongo
dc --profile tooling run --rm security-db-migrate
dc --profile tooling run --rm workflow-onboard-tenant-db-migrate
dc --profile tooling run --rm identity-audit-db-migrate
dc up -d --wait