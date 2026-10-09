#!/bin/sh
# Instance-level setup: the shared extension and one connection user per schema (Annex J, J.7).
# The image runs it once, on an empty volume. Run it by hand when a schema is added (J.5.5), so it
# must be safe to repeat: a user that exists keeps its password, and nothing is dropped or reset.
# Schemas, tables, the _reader/_writer roles and grants belong to each -db, not to this script.
set -e

# The only list of schemas of this repository (D-03). A schema added later goes here.
SCHEMAS="
commercial_reservation
operations_cost
cash_reporting
security
workflow_onboard_tenant
workflow_register_payment
workflow_execute_refund
workflow_cancel_departure
workflow_change_departure_vehicles
"

run_psql() { psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" "$@"; }

run_psql -c "CREATE EXTENSION IF NOT EXISTS pgcrypto"

for schema in $SCHEMAS; do
  var="$(printf '%s' "$schema" | tr 'a-z' 'A-Z')_APP_PASSWORD"
  password="$(printenv "$var" || true)"
  if [ -z "$password" ]; then
    echo "ERROR: $var is required, set it in env/<environment>.env" >&2
    exit 1
  fi
  # The password travels in the environment and is quoted by format('%L'): it never shows in a
  # process list and a quote inside it cannot break the statement.
  APP_PASSWORD="$password" run_psql -v schema="$schema" <<'SQL'
\getenv pw APP_PASSWORD
SELECT format('CREATE ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD %L', :'schema' || '_app', :'pw')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'schema' || '_app')
\gexec
SELECT format('ALTER ROLE %I SET search_path = %I', :'schema' || '_app', :'schema')
\gexec
SQL
done
