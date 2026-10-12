#!/bin/sh
# The V checks of the spec (RN-INF-01 to RN-INF-05) against a throwaway instance. CI and a
# developer run this same file; Docker is the only requirement.
#
# It never touches dev, qa or main: it starts the project multi-tour-ci from a variables file built
# in a temporary directory with passwords generated now, so no secret is written in the repository.
# Removing a volume is allowed only for that throwaway project (Annex J, J.5.4).
set -u
cd "$(dirname "$0")/.." || exit 1

# Git Bash on Windows rewrites container paths such as /docker-entrypoint-initdb.d; no effect elsewhere
export MSYS_NO_PATHCONV=1

PROJECT="multi-tour-ci"
SCHEMAS="commercial_reservation operations_cost cash_reporting security
workflow_onboard_tenant workflow_register_payment workflow_execute_refund
workflow_cancel_departure workflow_change_departure_vehicles"

started=$(date +%s)
TMP=$(mktemp -d) || exit 1
ENVF="$TMP/ci.env"
# the native docker client needs a Windows path for the file; elsewhere cygpath does not exist
ENVF_ARG="$ENVF"
command -v cygpath >/dev/null 2>&1 && ENVF_ARG=$(cygpath -m "$ENVF")
# every include of platform.yml reads this file (its env_file is COMPOSE_ENV_FILE)
export COMPOSE_ENV_FILE="$ENVF_ARG"
BASE=$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')
fail=0

# One distinct password per user, derived from a random base that lives only in this process. The
# quote at the end exercises the escaping of the init script (plan, Risks).
password() { printf "%s-%s'x" "$BASE" "$1"; }

# -p wins over the file, so no variable can make this script address another environment
dc() { docker compose -p "$PROJECT" --env-file "$ENVF_ARG" "$@"; }

cleanup() {
  dc down -v --remove-orphans >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT
trap 'exit 1' INT TERM

build_env() {
  src=env/dev.env.example
  if [ ! -f "$src" ]; then : > "$ENVF"; return 0; fi
  while IFS= read -r line; do
    case $line in
      \#*) printf '%s\n' "$line" ;;
      COMPOSE_PROJECT_NAME=*) printf 'COMPOSE_PROJECT_NAME=%s\n' "$PROJECT" ;;
      PG_ADMIN_PASSWORD=*) printf 'PG_ADMIN_PASSWORD="%s"\n' "$(password admin)" ;;
      MONGO_INITDB_ROOT_PASSWORD=*) printf 'MONGO_INITDB_ROOT_PASSWORD="%s"\n' "$(password mongo-admin)" ;;
      *_APP_PASSWORD=*)
        name=${line%%=*}
        schema=$(printf '%s' "${name%_APP_PASSWORD}" | tr 'A-Z' 'a-z')
        printf '%s="%s"\n' "$name" "$(password "$schema")" ;;
      *) printf '%s\n' "$line" ;;
    esac
  done < "$src" > "$ENVF"
}

value() { sed -n "s/^$1=//p" "$ENVF" | head -1; }
psql_admin() { dc exec -T postgres psql -U "$ADMIN" -d "$DB" -v ON_ERROR_STOP=1 -tA "$@"; }

run() { # name, function
  if reason=$("$2" 2>&1); then
    echo "PASS  $1"
  else
    echo "FAIL  $1"
    [ -n "$reason" ] && printf '%s\n' "$reason" | sed 's/^/        /'
    fail=1
  fi
}

V_one_postgres_container_per_environment() {
  services=$(dc config --services 2>&1) || { echo "docker compose config failed: compose.yml is missing or invalid"; return 1; }
  [ "$services" = "postgres" ] || { echo "services are '$(echo $services)', expected exactly 'postgres'"; return 1; }
  images=$(dc config --images 2>/dev/null)
  printf '%s\n' "$images" | grep -Eq '^postgres:[0-9]+\.[0-9]+(-alpine)?$' || { echo "image '$images' is not pinned to an exact version"; return 1; }
  printf '%s\n' "$images" | grep -q 'latest' && { echo "image uses latest"; return 1; }
  # the resolved file holds the passwords, so it is only searched, never printed
  dc config 2>/dev/null | grep -Eq '^[[:space:]]+ports:' && { echo "the resolved configuration publishes ports (D-04)"; return 1; }
  [ "$STARTED" = 1 ] || { echo "the instance did not start healthy"; return 1; }
  ids=$(dc ps -q)
  [ "$(printf '%s\n' "$ids" | grep -c .)" = 1 ] || { echo "expected exactly one container"; return 1; }
  [ "$(docker inspect -f '{{.State.Health.Status}}' "$ids")" = healthy ] || { echo "the container is not healthy"; return 1; }
}

V_init_runs_only_on_empty_volume() {
  psql_admin -c "CREATE TABLE IF NOT EXISTS public.verify_marker (v text); INSERT INTO public.verify_marker VALUES ('kept')" >/dev/null || { echo "could not write the marker row"; return 1; }
  dc restart postgres >/dev/null 2>&1
  dc up -d --wait --wait-timeout 120 postgres >/dev/null 2>&1 || { echo "the instance did not come back healthy"; return 1; }
  [ "$(psql_admin -c "SELECT count(*) FROM public.verify_marker WHERE v = 'kept'")" = 1 ] || { echo "the marker row is gone after the restart"; return 1; }
  dc logs postgres 2>&1 | grep -q 'Skipping initialization' || { echo "the log does not say the initialization was skipped"; return 1; }
}

V_no_real_env_file_versioned() {
  # tracked files plus untracked ones that git would not ignore, i.e. what a commit could take
  listed=$(git ls-files --cached --others --exclude-standard | grep -E '(^|/)\.env$|^env/[^/]+\.env$')
  [ -z "$listed" ] || { echo "a real variables file is versionable: $listed"; return 1; }
  [ "$(git check-ignore env/dev.env)" = "env/dev.env" ] || { echo "env/dev.env is not ignored"; return 1; }
  [ -z "$(git check-ignore env/dev.env.example)" ] || { echo "env/dev.env.example is ignored but must be versioned"; return 1; }
}

V_every_schema_has_its_app_user() {
  for schema in $SCHEMAS; do
    user="${schema}_app"
    row=$(psql_admin -c "SELECT rolcanlogin, rolsuper, rolcreatedb, rolcreaterole FROM pg_roles WHERE rolname = '$user'")
    [ "$row" = "t|f|f|f" ] || { echo "$user is missing, cannot log in, or has too many privileges ('$row')"; return 1; }
    [ "$(psql_admin -c "SELECT count(*) FROM pg_db_role_setting s JOIN pg_roles r ON r.oid = s.setrole WHERE r.rolname = '$user' AND s.setdatabase = 0 AND s.setconfig @> ARRAY['search_path=$schema']")" = 1 ] || { echo "$user has no search_path set to $schema"; return 1; }
    # -h postgres leaves the container's trust rule for localhost, so the password is really checked
    got=$(dc exec -T -e PGPASSWORD="$(password "$schema")" postgres psql -h postgres -U "$user" -d "$DB" -tAc "SELECT current_user || ':' || current_setting('search_path')" 2>&1) || { echo "$user cannot connect with its own password"; return 1; }
    [ "$got" = "$user:$schema" ] || { echo "$user connected as '$got'"; return 1; }
    dc exec -T -e PGPASSWORD="wrong-$BASE" postgres psql -h postgres -U "$user" -d "$DB" -tAc "SELECT 1" >/dev/null 2>&1 && { echo "$user accepted a wrong password"; return 1; }
  done
  return 0
}

# The services check the issuer and the audience only when they are set: an empty example would leave any issuer and any audience accepted
# as long as the signature is valid, so the example names what the security microservice signs with (plan HU-SEC-001, D-02)
V_examples_name_the_issuer_and_audience_of_the_security_microservice() {
  for environment in dev qa main; do
    example="env/$environment.env.example"
    grep -Eq '^JWT_ISSUER=multi-tour-security[[:space:]]*$' "$example" || { echo "$example does not say JWT_ISSUER=multi-tour-security"; return 1; }
    grep -Eq '^JWT_AUDIENCE=multi-tour[[:space:]]*$' "$example" || { echo "$example does not say JWT_AUDIENCE=multi-tour"; return 1; }
  done
}

snapshot() { # roles with their password hashes, so a reset password shows as a difference
  psql_admin -c "SELECT rolname, rolsuper, rolcanlogin, rolcreatedb, rolcreaterole, rolpassword FROM pg_authid ORDER BY 1" \
             -c "SELECT r.rolname, s.setconfig FROM pg_db_role_setting s LEFT JOIN pg_roles r ON r.oid = s.setrole ORDER BY 1"
}

V_init_runs_twice_without_error() {
  snapshot > "$TMP/before.txt" || { echo "could not read the roles"; return 1; }
  out=$(dc exec -T postgres sh /docker-entrypoint-initdb.d/01-instance.sh 2>&1) || { echo "the second run failed:"; printf '%s\n' "$out" | tail -n 5; return 1; }
  snapshot > "$TMP/after.txt" || { echo "could not read the roles"; return 1; }
  cmp -s "$TMP/before.txt" "$TMP/after.txt" || { echo "the second run changed roles or settings"; return 1; }
}


# ---- the root composition (spec 001-hu-inf-001, RN-INF-01 to RN-INF-04): it is only resolved, never started
# -f platform.yml and the same throwaway project: what Docker would run is what is read
dcp() { docker compose -p "$PROJECT" -f platform.yml --env-file "$ENVF_ARG" "$@"; }

# The repositories the composition includes sit beside this one; the CI has only this one, so it gets the rest
SIBLING_REPOS="multi-tour-infra-mongo multi-tour-identity-audit-api multi-tour-identity-audit-db multi-tour-security multi-tour-workflow-onboard-tenant multi-tour-worker-event-relay multi-tour-api-gateway multi-tour-front"
siblings() {
  for repo in $SIBLING_REPOS; do
    [ -d "../$repo" ] || git clone -q --depth 1 -b develop "https://github.com/code-corhuila/$repo.git" "../$repo" || { echo "could not get $repo"; return 1; }
  done
}

I_root_composition_publishes_no_port_of_the_api() {
  siblings || return 1
  out=$(dcp config 2>&1) || { echo "the root composition does not resolve:"; printf '%s\n' "$out" | tail -n 3; return 1; }
  # the gateway is the only service with ports (norm 5.6.1)
  printf '%s\n' "$out" | awk '/^  [a-z0-9-]+:/ {svc=$1} /^    ports:/ {print svc}' | grep -vx 'api-gateway:' | grep -q . && { echo "a service other than api-gateway publishes ports (norm 5.6.1)"; return 1; }
  printf '%s\n' "$out" | awk '/^  api-gateway:/ {f=1; next} /^  [a-z]/ {f=0} f && /^    ports:/ {ok=1} END {exit !ok}' || { echo "api-gateway does not publish its port"; return 1; }
  printf '%s\n' "$out" | awk '/^  identity-audit-api:/ {f=1; next} /^  [a-z]/ {f=0} f && /^    expose:/ {e=1; next} f && e && /8082/ {ok=1} f && /^    [a-z_]+:/ && !/^    expose:/ {e=0} END {exit !ok}' || { echo "identity-audit-api does not expose 8082"; return 1; }
}

I_missing_sibling_fails_with_its_name() {
  out=$(SIBLINGS_DIR="$TMP/none" ENV_FILE="$ENVF" sh scripts/up.sh dev --check 2>&1) && { echo "up.sh accepted an empty folder of siblings"; return 1; }
  printf '%s\n' "$out" | grep -q 'multi-tour-identity-audit-api' || { echo "the message does not name the missing repository"; return 1; }
}

I_runner_waits_for_the_healthy_instance_and_is_not_started_by_up() {
  siblings || return 1
  dcp config --services 2>/dev/null | grep -q 'identity-audit-db-migrate' && { echo "the runner starts with up (it needs the profile tooling)"; return 1; }
  out=$(dcp --profile tooling config 2>&1) || { echo "the composition with the profile tooling does not resolve"; return 1; }
  printf '%s\n' "$out" | awk '/^  identity-audit-db-migrate:/ {f=1; next} /^  [a-z]/ {f=0} f && /condition: service_healthy/ {ok=1} END {exit !ok}' || { echo "the runner does not wait for service_healthy"; return 1; }
}

I_up_script_checks_the_siblings_and_resolves_the_composition() {
  siblings || return 1
  out=$(ENV_FILE="$ENVF" sh scripts/up.sh dev --check 2>&1) || { echo "up.sh --check failed:"; printf '%s\n' "$out" | tail -n 3; return 1; }
}

I_root_composition_has_every_service_of_the_demo() {
  siblings || return 1
  services=$(dcp --profile tooling config --services 2>&1) || { echo "the composition with the profile tooling does not resolve"; return 1; }
  for svc in postgres mongo security security-db-migrate identity-audit-api identity-audit-db-migrate workflow-onboard-tenant workflow-onboard-tenant-db-migrate worker-event-relay front api-gateway; do
    printf '%s\n' "$services" | grep -qx "$svc" || { echo "the root composition lacks the service $svc"; return 1; }
  done
}

# The gateway routes by container name (its routes/*.conf): the services must answer to those names on the platform network
I_services_answer_to_the_names_the_gateway_routes_to() {
  siblings || return 1
  out=$(dcp config 2>&1) || { echo "the root composition does not resolve"; return 1; }
  for alias in multi-tour-security multi-tour-identity-audit-api multi-tour-workflow-onboard-tenant multi-tour-front; do
    printf '%s\n' "$out" | grep -Eq "^[[:space:]]+- $alias\$" || { echo "no service has the network alias $alias"; return 1; }
  done
  printf '%s\n' "$out" | grep -Eq 'LISTEN_ADDR: "?:8090"?' || { echo "the saga does not listen on 8090, where the gateway sends it"; return 1; }
  printf '%s\n' "$out" | grep -Eq 'http://127\.0\.0\.1:8090/health' || { echo "the saga health check does not ask port 8090, where it listens"; return 1; }
}

I_demo_front_port_is_a_separate_opt_in_file() {
  siblings || return 1
  [ -f demo-front-port.yml ] || { echo "demo-front-port.yml is missing"; return 1; }
  out=$(docker compose -p "$PROJECT" -f platform.yml -f demo-front-port.yml --env-file "$ENVF_ARG" config 2>&1) || { echo "platform.yml with demo-front-port.yml does not resolve"; return 1; }
  printf '%s\n' "$out" | awk '/^  front:/ {f=1; next} /^  [a-z]/ {f=0} f && /^    ports:/ {ok=1} END {exit !ok}' || { echo "the front does not publish its port with the opt-in file"; return 1; }
}

# ---- setup: a clean throwaway project, then one instance
build_env
dc down -v --remove-orphans >/dev/null 2>&1 || true
docker network inspect platform >/dev/null 2>&1 || docker network create platform >/dev/null
ADMIN=$(value PG_ADMIN_USER)
DB=$(value PG_DATABASE)
STARTED=0
dc up -d --wait --wait-timeout 120 postgres >"$TMP/up.log" 2>&1 && STARTED=1

run "V·one_postgres_container_per_environment" V_one_postgres_container_per_environment
run "V·init_runs_only_on_empty_volume" V_init_runs_only_on_empty_volume
run "V·no_real_env_file_versioned" V_no_real_env_file_versioned
run "V·examples_name_the_issuer_and_audience_of_the_security_microservice" V_examples_name_the_issuer_and_audience_of_the_security_microservice
run "V·every_schema_has_its_app_user" V_every_schema_has_its_app_user
run "V·init_runs_twice_without_error" V_init_runs_twice_without_error
run "I·root_composition_publishes_no_port_of_the_api" I_root_composition_publishes_no_port_of_the_api
run "I·missing_sibling_fails_with_its_name" I_missing_sibling_fails_with_its_name
run "I·runner_waits_for_the_healthy_instance_and_is_not_started_by_up" I_runner_waits_for_the_healthy_instance_and_is_not_started_by_up
run "I·up_script_checks_the_siblings_and_resolves_the_composition" I_up_script_checks_the_siblings_and_resolves_the_composition
run "I:root_composition_has_every_service_of_the_demo" I_root_composition_has_every_service_of_the_demo
run "I:services_answer_to_the_names_the_gateway_routes_to" I_services_answer_to_the_names_the_gateway_routes_to
run "I:demo_front_port_is_a_separate_opt_in_file" I_demo_front_port_is_a_separate_opt_in_file

echo "finished in $(( $(date +%s) - started )) s"
[ "$fail" = 0 ] && echo "ALL CHECKS PASSED" || echo "SOME CHECKS FAILED"
exit "$fail"
