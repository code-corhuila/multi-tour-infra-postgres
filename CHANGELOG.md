# Changelog

All notable changes of `multi-tour-infra-postgres` (Single PostgreSQL instance and root composition) are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [3.0.0] - 2026-11-14

Cut 3 release. Every entry below is a pull request merged into `qa` and re-applied to `release/3.0.0` with `git cherry-pick -x`; the heading of each group is the user story named in the pull request, and the entry is the title of the pull request without its type. The frozen head of `qa` is `bf97f6daac6f6a0e97a0e2fe79c613a54d67d883`.

### Changed

#### HU-CSH-001 - Operate the daily cash

- The cash reporting api and its runner ([PR 24](https://github.com/code-corhuila/multi-tour-infra-postgres/pull/24))

#### HU-FRT-001 - Mount the four portals in one container

- The cash-reporting portal include ([PR 20](https://github.com/code-corhuila/multi-tour-infra-postgres/pull/20))

#### HU-INF-001 - Run the single PostgreSQL instance and the root composition

- HU-INF-001, HU-WRK-003 ([PR 50](https://github.com/code-corhuila/multi-tour-infra-postgres/pull/50))

#### HU-WRK-005 - Enforce the reprogramming deadlines

- The reprogramming timers worker ([PR 38](https://github.com/code-corhuila/multi-tour-infra-postgres/pull/38))

#### HU-WRK-007 - Relay events between domains

- The platform composition and relay addresses ([PR 36](https://github.com/code-corhuila/multi-tour-infra-postgres/pull/36))

#### Cross-cutting: CI, test fixes and alignment promotions (no single story is named in the PR title, branch or body)

- Sagas and cash workers composition ([PR 42](https://github.com/code-corhuila/multi-tour-infra-postgres/pull/42))
- The cash reporting env variables ([PR 44](https://github.com/code-corhuila/multi-tour-infra-postgres/pull/44))

### Security

#### HU-INF-001 - Run the single PostgreSQL instance and the root composition

- Write the duration of the dev service tokens in hours ([PR 51](https://github.com/code-corhuila/multi-tour-infra-postgres/pull/51))

[Unreleased]: https://github.com/code-corhuila/multi-tour-infra-postgres/compare/v3.0.0...HEAD
[3.0.0]: https://github.com/code-corhuila/multi-tour-infra-postgres/releases/tag/v3.0.0
