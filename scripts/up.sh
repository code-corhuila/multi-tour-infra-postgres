#!/bin/sh
# Starts the PostgreSQL instance of one environment and waits until it is healthy.
# Usage: scripts/up.sh dev|qa|main
set -eu
cd "$(dirname "$0")/.."

env_name="${1:-}"
case "$env_name" in
  dev|qa|main) ;;
  *) echo "usage: scripts/up.sh dev|qa|main" >&2; exit 2 ;;
esac

env_file="env/$env_name.env"
if [ ! -f "$env_file" ]; then
  echo "ERROR: $env_file does not exist. Copy env/$env_name.env.example to $env_file and fill the secrets." >&2
  exit 1
fi

# The other repositories join this network by name, so it cannot belong to this compose file (D-05)
docker network inspect platform >/dev/null 2>&1 || docker network create platform >/dev/null

docker compose --env-file "$env_file" up -d --wait postgres
