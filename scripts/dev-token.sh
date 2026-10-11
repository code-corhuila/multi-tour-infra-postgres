#!/bin/sh
# Development only (develop): prints the service token of a worker or a saga, made by the security service with
# its own command. In qa and main the tokens are secrets of the environment.
# Usage: scripts/dev-token.sh <name> [duration]     e.g. scripts/dev-token.sh worker-event-relay 24h
# The name becomes the `sub` of the token. Paste the line into env/dev.env as SERVICE_TOKEN (the relay) or
# WORKFLOW_ONBOARD_TENANT_SERVICE_TOKEN (the saga). Needs the keys (scripts/dev-keys.sh) and the images built.
set -eu
cd "$(dirname "$0")/.."

name="${1:-}"
if [ -z "$name" ]; then
  echo "usage: scripts/dev-token.sh <name> [duration]" >&2
  exit 2
fi
if [ ! -f env/dev.env ]; then
  echo "ERROR: env/dev.env does not exist. Copy env/dev.env.example and run scripts/dev-keys.sh first." >&2
  exit 1
fi

export COMPOSE_ENV_FILE="$(pwd)/env/dev.env"
# --no-deps: the command needs only the private key, not the database
docker compose -f platform.yml --env-file env/dev.env run --rm --no-deps -T security issue-service-token "$name" "${2:-24h}"
