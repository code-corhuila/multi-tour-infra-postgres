# multi-tour-infra-postgres

> Single PostgreSQL instance of the project (container and volume), root composition, environments and secrets

Part of the **Multi Tour** distributed system — team `multi-tour`, Grupo 2.
Governance and documentation live in [`multi-tour-docs`](https://github.com/code-corhuila/multi-tour-docs).
## What it is

The single PostgreSQL instance of the platform (Annex J): one container and one volume per
environment, the `pgcrypto` extension, and one connection user `<schema>_app` per schema, with
its `search_path`. It is **not** where schemas, tables or migrations live: each `-db` repository
owns its schema and runs its own migrations against this instance. It publishes no port; only the
gateway does.

## How to start it

Needs Docker with Compose v2. Pick the environment: `dev`, `qa` or `main`.

```sh
cp env/dev.env.example env/dev.env   # never versioned; fill every secret
sh scripts/up.sh dev                 # the whole platform (platform.yml): creates the network platform and waits until healthy
sh scripts/up.sh dev --check         # only checks that the sibling repositories are there and the composition resolves
sh scripts/down.sh dev               # stops it and keeps the data
```

The repositories that `platform.yml` includes (`multi-tour-infra-mongo`, `multi-tour-identity-audit-api` and `-db`, `multi-tour-security`, `multi-tour-workflow-onboard-tenant`, `multi-tour-worker-event-relay`, `multi-tour-api-gateway`, `multi-tour-front`) must be cloned as siblings of this one, in the same folder; `up.sh` names the one that is missing and the command to clone it, and `down.sh` needs them too. `MONGODB_URI` repeats the password of `IDENTITY_AUDIT_APP_PASSWORD`: keep both equal, and write a password with reserved characters percent-encoded in the address.

`up.sh` starts in order: the instances (PostgreSQL, MongoDB), the migration runners (security, the saga, identity-audit), then the services. Only the gateway publishes a port (8080). The browser must also reach the front: `up.sh dev --demo` adds `demo-front-port.yml`, which publishes it on 4200 and nothing else. Small files in `glue/` give two services the container name the gateway routes to and set the port of the saga (8090), and define the front, which has no compose file of its own. Run one environment at a time: the network `platform` and the host port 8080 are shared.

## Demo walkthrough (development only)

```sh
sh scripts/dev-keys.sh                     # RS256 pair in keys/ (ignored); paste the three lines it prints into env/dev.env
# fill env/dev.env: every password, ALLOWED_ORIGIN=http://localhost:4200, MONGODB_URI with the same password
sh scripts/up.sh dev --demo                # refuses to start while a CHANGE_ME is left
sh scripts/dev-token.sh worker-event-relay # paste the line as SERVICE_TOKEN
sh scripts/dev-token.sh workflow-onboard-tenant   # paste it as WORKFLOW_ONBOARD_TENANT_SERVICE_TOKEN
sh scripts/up.sh dev --demo                # again, now with both tokens
```

The first Platform Administrator is made once with the command of the security service (`bootstrap-platform-admin`, see its README), through a script:

```sh
sh scripts/bootstrap-admin.sh admin@example.com   # or PLATFORM_ADMIN_EMAIL in env/dev.env; asks the password without echo
```

Run it with the stack up. The password goes to the security service through standard input only (never an argument or a variable) and is never printed; with an administrator already there it does nothing, so repeating it is harmless. Then, in the browser:

1. Open `http://localhost:8080/platform` (the gateway: it serves the front and the API on one origin; port 4200 is only the front and answers 405 to any API call) and sign in as the Platform Administrator.
2. Register a tenant in the portal: it starts the onboarding saga and shows the identifier of the new tenant.
3. Open `http://localhost:8080/t/<identifier>`: the public profile of the tenant.
4. Sign up as a customer of that tenant and sign in.
5. Each role sees its own screen: the Platform Administrator the tenants list, the customer the customer area.

## Isolation of one microservice (for the professor)

The gateway resolves names on every request and answers `503` for a service that is down, and the front shell is a separate container. Stop one service and the rest keep working:

```sh
# any route of security or of the saga answers with the service's own status (401 without a token), never 503
curl -i http://localhost:8080/api/v1/security/users
docker compose -f platform.yml --env-file env/dev.env stop identity-audit-api
curl -i -H 'Authorization: Bearer x' http://localhost:8080/api/v1/identity-audit/tenants   # 503 {"error":"SERVICE_UNAVAILABLE",...}
curl -i http://localhost:8080/api/v1/security/users   # unchanged
curl -i http://localhost:8080/                                # 200: the front shell still loads
docker compose -f platform.yml --env-file env/dev.env start identity-audit-api
```

Expected: only the stopped service's route answers `503`; the other routes and the front shell answer as before; after `start`, the route answers again. The portal is its own container (`multi-tour-identity-audit-portal`, from `../multi-tour-identity-audit-portal/deploy/`). The gateway maps `/portals/identity-audit-portal.js` and `.css` to it, so stopping it (`docker compose -f platform.yml --env-file env/dev.env stop multi-tour-identity-audit-portal`) takes only that area down: the module answers `503` and the front shows "service unavailable" in that area while the other areas keep working.

### Rebuild after a portal, gateway or front change (dev)

The portal image no longer travels inside the front image. A stack started before this change still serves the old bundle; to run the new one:

```sh
export COMPOSE_ENV_FILE="$(pwd)/env/dev.env"   # up.sh sets it; a manual compose needs it
docker compose -f platform.yml --env-file env/dev.env build multi-tour-identity-audit-portal api-gateway front
docker compose -f platform.yml --env-file env/dev.env up -d --force-recreate multi-tour-identity-audit-portal api-gateway front
```

Then hard-reload the browser (Ctrl+F5): the module is served with `Cache-Control: no-store`, but a tab opened before still holds the old one. `COMPOSE_PROJECT_NAME` comes from `env/<env>.env` (`multi-tour-dev`, `-qa`, `-main`), so the same commands with `qa` or `main` act on that environment only; never add `-v` there.

Each environment has its own `COMPOSE_PROJECT_NAME` (`multi-tour-dev`, `-qa`, `-main`), so each
one gets its own container and volume.

- In `qa` and `main`, never run `docker compose down -v` or delete the volume, and back up
  before migrating (J.5.4). `scripts/down.sh` refuses `-v`.
- When a schema is added, add it to the list in `postgres/init/01-instance.sh` and run the script
  again by hand (J.5.5); it keeps existing users and their passwords:
  `docker compose --env-file env/dev.env exec postgres sh /docker-entrypoint-initdb.d/01-instance.sh`

## Where the data is

Database `PG_DATABASE` (`multitour`), administered by `PG_ADMIN_USER`, in the volume
`postgres-data` of the environment. One user per schema of `01-instance.sh` (the three
PostgreSQL domains, `security` and the five sagas), e.g. `commercial_reservation_app`, each with
the password `<SCHEMA>_APP_PASSWORD` of the environment file. There is no published port;
open `psql` inside the container:

```sh
docker compose --env-file env/dev.env exec postgres psql -U multitour_admin -d multitour
```

## How to test it

```sh
sh tests/verify.sh
```

Needs Docker. It starts a throw-away project, runs the five checks of the spec (one container
per environment, the init script only on an empty volume, no real `.env` versioned, every schema
with its user, the init script twice without changes) and removes it. The CI runs the same
script on every pull request to `develop` and `qa`.

## What is missing

Observability, backups, and the services of the other domains and sagas, which come with their
stories (`code-corhuila/multi-tour-docs#199`).


## Branching

Three permanent branches. **None of them accepts a direct commit** — you enter through a child
branch and leave through a Pull Request.

```
develop  <--PR--  feat/... fix/... chore/...
qa       <--PR--  qa/...
main     <--PR--  release/...  hotfix/...
```

Promotion happens **by re-application** (`git cherry-pick -x`), never by merging one permanent
branch into another: `merge develop -> qa` and `merge qa -> main` do not exist in this model.

`main` requires **1 approval from `ariel5253`**. On `develop` and `qa` the team sets its own review
rule.

Full policy: `00-governance/branching-policy.md` in `multi-tour-docs`.
