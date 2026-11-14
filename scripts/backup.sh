#!/bin/sh
# Writes one dated backup of the PostgreSQL database (every schema) and one of the MongoDB instance, outside the
# volumes, and deletes the backups of that environment older than 30 days (ADR-004 D9, PDR §17).
# Usage: scripts/backup.sh dev|qa|main
# The scheduler is the environment's (a daily cron of the host), never a worker (Annex D, rule 8).
# ENV_FILE and BACKUP_ROOT replace the variables file and the folder of the backups (backups/<environment>).
set -eu
cd "$(dirname "$0")/.."

env_name="${1:-}"
case "$env_name" in
  dev|qa|main) ;;
  *) echo "usage: scripts/backup.sh dev|qa|main" >&2; exit 2 ;;
esac
[ "$#" -eq 1 ] || { echo "usage: scripts/backup.sh dev|qa|main" >&2; exit 2; }

env_file="${ENV_FILE:-env/$env_name.env}"
if [ ! -f "$env_file" ]; then
  echo "ERROR: $env_file does not exist. Copy env/$env_name.env.example to $env_file and fill the secrets." >&2
  exit 1
fi
case "$env_file" in /*|[A-Za-z]:*) COMPOSE_ENV_FILE="$env_file" ;; *) COMPOSE_ENV_FILE="$(pwd)/$env_file" ;; esac
export COMPOSE_ENV_FILE
# COMPOSE_FILE is the variable of Compose itself; the checks add a file to it
export COMPOSE_FILE="${COMPOSE_FILE:-platform.yml}"

root="${BACKUP_ROOT:-backups/$env_name}"
date=$(date -u +%Y-%m-%d)
dir="$root/$date"
# Both dumps go to a partial folder that replaces the dated one only when both succeed: a failed second backup
# of the same day leaves the good one as it was. Created here, not by Docker, so this user can delete it later.
partial="$dir.partial-$$"
trap 'rm -rf "$partial" "$dir.old-$$"' EXIT
mkdir -p "$partial"
BACKUP_DIR=$(cd "$partial" && pwd)
command -v cygpath >/dev/null 2>&1 && BACKUP_DIR=$(cygpath -m "$BACKUP_DIR")
export BACKUP_DIR

docker compose --env-file "$env_file" --profile tooling run --rm postgres-backup
docker compose --env-file "$env_file" --profile tooling run --rm mongo-backup
[ ! -e "$dir" ] || mv "$dir" "$dir.old-$$"
mv "$partial" "$dir"
echo "backup written to $dir"

# Only after a good backup: the dated folders older than 30 days go (GNU date, else BSD date)
cutoff=$(date -u -d '30 days ago' +%Y%m%d 2>/dev/null || date -u -v-30d +%Y%m%d)
for old in "$root"/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]; do
  [ -d "$old" ] || continue
  if [ "$(basename "$old" | tr -d -)" -lt "$cutoff" ]; then
    rm -rf "$old"
    echo "deleted $old (older than 30 days)"
  fi
done
