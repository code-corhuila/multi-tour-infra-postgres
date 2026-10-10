#!/bin/sh
# Stops the platform of one environment (everything platform.yml includes) and keeps its volumes.
# Usage: scripts/down.sh dev|qa|main
set -eu
cd "$(dirname "$0")/.."

for arg in "$@"; do
  case "$arg" in
    -v|--volumes)
      echo "ERROR: $arg is refused. The volume is the history of the system and is never removed (Annex J, J.5.4)." >&2
      exit 2 ;;
  esac
done

env_name="${1:-}"
case "$env_name" in
  dev|qa|main) ;;
  *) echo "usage: scripts/down.sh dev|qa|main" >&2; exit 2 ;;
esac
if [ "$#" -ne 1 ]; then
  echo "usage: scripts/down.sh dev|qa|main (it takes no other argument)" >&2
  exit 2
fi

env_file="env/$env_name.env"
if [ ! -f "$env_file" ]; then
  echo "ERROR: $env_file does not exist. Copy env/$env_name.env.example to $env_file and fill the secrets." >&2
  exit 1
fi

docker compose -f platform.yml --env-file "$env_file" down
