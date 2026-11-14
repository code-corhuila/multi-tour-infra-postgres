#!/bin/sh
# Brings the PostgreSQL database and the MongoDB instance of one environment back to a dated backup of
# scripts/backup.sh (ADR-004 D9). It replaces what they hold now, so in qa and main it needs --yes (J.5.4).
# Usage: scripts/restore.sh dev|qa|main <YYYY-MM-DD> [--yes]
# Stop the services first (not the instances), so no request writes while the data comes back.
# ENV_FILE and BACKUP_ROOT replace the variables file and the folder of the backups (backups/<environment>).
set -eu
cd "$(dirname "$0")/.."

usage() { echo "usage: scripts/restore.sh dev|qa|main <YYYY-MM-DD> [--yes]" >&2; exit 2; }
env_name="${1:-}"
date="${2:-}"
case "$env_name" in dev|qa|main) ;; *) usage ;; esac
case "$date" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) usage ;; esac
yes=0
case "$#:${3:-}" in
  2:) ;;
  3:--yes) yes=1 ;;
  *) usage ;;
esac

if [ "$env_name" != dev ] && [ "$yes" != 1 ]; then
  echo "ERROR: restoring replaces the data of $env_name with the backup of $date. Run it again with --yes to confirm." >&2
  exit 2
fi

env_file="${ENV_FILE:-env/$env_name.env}"
if [ ! -f "$env_file" ]; then
  echo "ERROR: $env_file does not exist. Copy env/$env_name.env.example to $env_file and fill the secrets." >&2
  exit 1
fi
case "$env_file" in /*|[A-Za-z]:*) COMPOSE_ENV_FILE="$env_file" ;; *) COMPOSE_ENV_FILE="$(pwd)/$env_file" ;; esac
export COMPOSE_ENV_FILE
export COMPOSE_FILE="${COMPOSE_FILE:-platform.yml}"

dir="${BACKUP_ROOT:-backups/$env_name}/$date"
for f in postgres.dump mongo.archive; do
  [ -s "$dir/$f" ] || { echo "ERROR: $dir/$f does not exist; scripts/backup.sh $env_name writes it." >&2; exit 1; }
done
BACKUP_DIR=$(cd "$dir" && pwd)
command -v cygpath >/dev/null 2>&1 && BACKUP_DIR=$(cygpath -m "$BACKUP_DIR")
export BACKUP_DIR

docker compose --env-file "$env_file" --profile tooling run --rm postgres-restore
docker compose --env-file "$env_file" --profile tooling run --rm mongo-restore
echo "restored $env_name from $dir"
