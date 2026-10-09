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
sh scripts/up.sh dev                 # creates the network platform and waits until healthy
sh scripts/down.sh dev               # stops it and keeps the data
```

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

The root composition with the other repositories, the migration runners of each `-db`, the
development keys and tokens, observability and backups (AC3 to AC6 of
`code-corhuila/multi-tour-docs#199`), which come with the story spec.


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
