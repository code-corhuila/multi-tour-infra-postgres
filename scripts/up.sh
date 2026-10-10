#!/bin/sh
# Brings up the platform of one environment through platform.yml and waits until it is healthy.
# Usage: scripts/up.sh dev|qa|main [--check]
#   --check  only verifies the sibling repositories and that the composition resolves; starts nothing
# The repositories it includes must sit beside this one. ENV_FILE and SIBLINGS_DIR replace the variables file
# and the folder that holds the siblings (the checks use them; a person rarely needs to).
set -eu
cd "$(dirname "$0")/.."

env_name="${1:-}"
mode="${2:-up}"
case "$env_name" in
  dev|qa|main) ;;
  *) echo "usage: scripts/up.sh dev|qa|main [--check]" >&2; exit 2 ;;
esac
case "$mode" in
  up|--check) ;;
  *) echo "usage: scripts/up.sh dev|qa|main [--check]" >&2; exit 2 ;;
esac

env_file="${ENV_FILE:-env/$env_name.env}"
if [ ! -f "$env_file" ]; then
  echo "ERROR: $env_file does not exist. Copy env/$env_name.env.example to $env_file and fill the secrets." >&2
  exit 1
fi

# A repository that platform.yml includes and that is not beside this one stops the start, with its name
siblings="${SIBLINGS_DIR:-..}"
missing=0
for repo in multi-tour-infra-mongo multi-tour-identity-audit-api multi-tour-identity-audit-db; do
  if [ ! -d "$siblings/$repo" ]; then
    echo "ERROR: $repo is missing in $siblings. Clone it: git clone https://github.com/code-corhuila/$repo.git $siblings/$repo" >&2
    missing=1
  fi
done
[ "$missing" = 0 ] || exit 1

if [ "$mode" = "--check" ]; then
  docker compose -f platform.yml --env-file "$env_file" config >/dev/null
  exit 0
fi

# The other repositories join this network by name, so it cannot belong to this compose file (D-05)
docker network inspect platform >/dev/null 2>&1 || docker network create platform >/dev/null

docker compose -f platform.yml --env-file "$env_file" up -d --wait
