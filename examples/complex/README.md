# Complex polyrepo example

This directory contains a **full Rails demo** — **`polyrepo_demo/`** — plus **`polyrepo/`** configuration sketches (Polyrun root config, Docker).

## What you get in `polyrepo_demo/`

| Layer | Purpose |
|-------|---------|
| **Databases** | `primary` + `cache` + **`warehouse`** (three SQLite files; `warehouse` uses `db/warehouse_migrate/`) |
| **Client apps** | Three **Vite** roots — **admin**, **store**, **portal** — each builds to `public/<app>/assets/*.js` |
| **Assets** | **`script/ci_prepare`** runs `npm install` / `npm run build` (all three clients) + Playwright browser install + **`Polyrun::Prepare::Assets`** digest markers — **not** per example |
| **E2E** | **RSpec only**: Capybara + `capybara-playwright-driver` + **`using_session`** for four logical “apps” on one Puma server |
| **APIs** | REST (`/api/v1/*`), GraphQL (`POST /graphql`), gRPC (`demo.v1.Demo` in test) |
| **Lattice** | 120 `lib/demo/lattice/cell_*.rb` units + paired specs (generated; gitignored; `spec/spec_helper.rb` runs `examples/script/generate_lattice_spec_suite.rb`) |

There is **no** separate JavaScript E2E package (no `playwright test` or Cypress). Cross-app and UI flows belong in **`spec/system`** and **`spec/integration`** so coverage merges cleanly with **`polyrun merge-coverage`**.

## Commands

```bash
cd examples
./bin/ci_prepare    # includes polyrepo_demo Vite builds

cd complex/polyrepo_demo
RAILS_ENV=test bin/rails db:prepare
bundle exec rspec
```

### Postgres parallel matrix (Docker)

Use **`../docker-compose.yml`** and **`../script/docker_polyrun_provision_demo.sh complex/polyrepo_demo`** with **`export PGPORT=5433 PGPASSWORD=postgres`**, then **`bin/polyrun run-shards`** — same flow as **`examples/README.md`**.

Parallel + merged coverage matches other demos: **`polyrun.yml`** → **`run-shards`** → fragment JSON per shard → **`merge-coverage`**. From **`polyrepo_demo`**, use **`./bin/rspec_parallel`** (same flow in one command). See **[../README.md](../README.md)** for **`polyrun config`**, default **`polyrun`** (no subcommand), path-only sharding, and matrix **`ci-shard-*`**.

## `polyrepo/` (sketches)

- **`polyrun.yml`** — example partition / `prepare.rails_root` pointing at **`polyrepo_demo`** (adjust paths when wiring CI).
- **`docker-compose.yml`** — optional Postgres/Redis for shard DB naming.
- **`spec/all_paths.txt`** — example path list for **`plan`**.

## See also

- **`../multi_capybara/README.md`** — dual Vite + sessions (lighter sibling).
- **`../TESTING_REQUIREMENTS.md`** — shared builds, DB contention, GVL.
- **`../README.md`** — Polyrun conventions across examples.
