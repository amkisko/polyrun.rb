# Polyrun examples

## Why?

These apps show Polyrun against a real Rails stack: multiple databases, Vite bundles, Capybara and Playwright, optional Docker Compose Postgres, `partition.paths_file` with large spec lists (100+ files), and merged coverage—without inventing integration from README prose alone.

## How?

1. From this directory, run `./bin/ci_prepare` once for shared asset builds and markers (each demo also has `script/ci_prepare`).
2. Pick a demo (for example `simple/simple_demo`), then `bundle install` and `RAILS_ENV=test bin/rails db:prepare`.
3. Run `bundle exec rspec`. For parallel runs with Postgres, use the Docker Compose section and `script/docker_polyrun_provision_demo.sh`.
4. Parallel Polyrun: `bin/polyrun -c polyrun.yml parallel-rspec --workers N` runs run-shards and merge-coverage in one step (optional `--` to change the test command), or run run-shards and merge-coverage separately—see Parallel runs + merged coverage below. Global options `-c`, `-v`, and `-h` must come before the subcommand.

Runnable Rails trees: `*/simple_demo`, `*/multi_demo`, `cost_balancing/rails_demo` (symlink to multi-database), `complex/polyrepo_demo`, and `complex/polyrepo/` (Polyrun config only). Demos use plan, prepare, env, run-shards, merge-coverage or report-coverage, with per-shard coverage JSON in CI.

Each runnable demo uses 120+ generated lattice specs for partition demos: `lib/demo/lattice/cell_*.rb` and `spec/demo/lattice/cell_*_spec.rb`, plus `spec/paths.txt`, produced by `examples/script/generate_lattice_spec_suite.rb` (default count 120). That output is gitignored; `spec/spec_helper.rb` runs the generator before RSpec discovers specs (so a plain `bundle exec rspec` works after clone). `POLYRUN_SKIP_LATTICE_GENERATE=1` skips generation. Each demo has `bin/rspec_parallel` wrapping `polyrun parallel-rspec`.

## Partition strategies (load balancing)

Supported `partition.strategy` values: `round_robin` (default), `random_round_robin`, `cost_binpack` (aliases `cost`, `binpack`, `timing`), `hrw` / `rendezvous`. Cost strategies need timing JSON from `merge-timing` output or `partition.timing_file`.

- Plan-only demos (no Rails): [partition_strategies/](partition_strategies/README.md) — `demo_plan.sh`, sample `polyrun.yml` snippets, `spec_paths.txt` and `polyrun_timing.json`.
- Cost-based splits and constraints: [cost_balancing/](cost_balancing/README.md) — `demo.sh`, `polyrun_rails.yml`, `partition_constraints.example.yml`.

## Fixtures / factories / parallel DB hooks

`Polyrun::Data` (CachedFixtures, ParallelProvisioning, optional FactoryBot instrumentation) is documented in [fixtures_and_parallel_data.md](fixtures_and_parallel_data.md). The simple demo wires `Polyrun::RSpec.install_parallel_provisioning!` and a CachedFixtures example in `simple/simple_demo/spec/polyrun/polyrun_data_optimizations_spec.rb`.

## Mandatory parallel / CI practices

Shared assets, fixtures, database contention, and the Ruby GVL are covered in [TESTING_REQUIREMENTS.md](TESTING_REQUIREMENTS.md). Each demo has `script/ci_prepare`; run `bin/ci_prepare` here once before fanning out parallel workers.

| Concern | Polyrun / pattern |
|--------|-------------------|
| Assets not rebuilt per worker | `Polyrun::Prepare::Assets`, `script/ci_prepare`, CI cache |
| Distinct DB per parallel worker | `Polyrun::Database::Shard`, `databases.shard_db_pattern` in `polyrun.yml`, `bin/polyrun env` |
| Coverage across shards | `Polyrun::Coverage::Rails` in spec_helper → `coverage/polyrun-fragment-<shard>.json` → merge-coverage |
| CPU-bound Ruby | Multi-process splits (`run-shards`), not threads alone |
| Cached expensive fixture setup | `Polyrun::Data::CachedFixtures` (see fixtures_and_parallel_data.md) |
| Serial vs parallel DB seeds | `Polyrun::Data::ParallelProvisioning` + `polyrun/rspec` or `polyrun/minitest` |

The [multi_capybara](multi_capybara/README.md) demo covers named Capybara sessions (admin, store, platform), Playwright options, and REST, GraphQL, and gRPC over the same domain—useful for coverage maps and partition splits under `spec/grpc`, `spec/requests`, `spec/integration`, and `spec/system`.

## Rails databases in every demo

| Example | Primary + cache (SQLite) | Shard DB naming (`polyrun.yml` → Postgres) | Front-end asset sources |
|--------|---------------------------|-----------------------------------------------|-------------------------|
| [simple](simple/README.md) | Yes: `primary` + `cache`, `db/cache_migrate/` | Yes: `databases:` block | Propshaft only |
| [multi_database](multi_database/README.md) | Same SQLite multi-DB layout | Yes: shared [docker-compose.yml](docker-compose.yml) + `bin/polyrun env` | Propshaft |
| [multi_capybara](multi_capybara/README.md) | Same multi-DB layout | Yes | Two Vite apps (admin + store) + Propshaft |
| [complex](complex/README.md) | Three DBs + three Vite clients (`polyrepo_demo`) | Yes: `polyrun.yml` sketches in `complex/polyrepo/` | RSpec-only E2E (Capybara + Playwright); no separate JS test runner |
| [cost_balancing](cost_balancing/README.md) | Uses `rails_demo` (same app as multi_database) | Yes | Propshaft (via shared demo) |

## Docker Compose (PostgreSQL for parallel shards)

[docker-compose.yml](docker-compose.yml) starts Postgres 16 (default host port 5433) and runs `docker/postgres-init/01-create-templates.sql` so template databases exist for each demo’s `databases.template_db`. Nested compose files (e.g. `multi_database/docker-compose.yml`, `complex/polyrepo/docker-compose.yml`) include this file.

1. `./script/docker_up.sh` — `docker compose up` and wait for health.
2. `export PGPORT=5433 PGPASSWORD=postgres` — demo `polyrun.yml` files leave `postgresql.port` unset so `PGPORT` applies (avoids clashing with another Postgres on 5432).
3. `./script/docker_polyrun_provision_demo.sh simple/simple_demo` — runs `bin/polyrun db:setup-template` then `db:setup-shard` for each index in `partition.shard_total`.
4. `bin/polyrun run-shards` — children get `DATABASE_URL` from `polyrun.yml` per shard.

```bash
cd examples
chmod +x script/docker_up.sh script/docker_polyrun_provision_demo.sh
./script/docker_up.sh
export PGPORT=5433 PGPASSWORD=postgres
./script/docker_polyrun_provision_demo.sh simple/simple_demo
cd simple/simple_demo
bundle exec ../../../bin/polyrun -c polyrun.yml parallel-rspec --workers 4
```

For SQLite-only runs without Docker, use `RAILS_ENV=test bin/rails db:prepare` as usual.

## Parallel runs + merged coverage (pattern)

### Why `bundle exec rspec` looks serial

A normal `bundle exec rspec` run is one Ruby process running examples in order. That is expected.

Parallelism here means multiple OS processes, each running RSpec on a subset of spec files (from `partition.paths_file` such as `spec/paths.txt`, or `spec/spec_paths.txt`, or the `spec/**/*_spec.rb` glob), started by `bin/polyrun run-shards`. Polyrun prints which source was used, then stderr lines before RSpec output, for example:

```text
polyrun run-shards: 120 spec path(s) from spec/paths.txt
polyrun run-shards: 120 spec path(s) -> 4 parallel worker processes (not Ruby threads); strategy=round_robin
polyrun run-shards: started shard 0 pid=12345 (30 file(s))
...
polyrun run-shards: 4 children running; RSpec output below may be interleaved.
...
polyrun run-shards: next step — merge with: polyrun merge-coverage ...
```

Child processes share the same terminal; RSpec lines from different shards can interleave—that means they ran concurrently, not a bug. Use `bin/polyrun -v ... run-shards` for per-shard file counts before spawn.

From any demo app directory (after `./script/ci_prepare` and `RAILS_ENV=test bin/rails db:prepare`):

```bash
# One command: run-shards + merge-coverage (default command: bundle exec rspec)
bin/polyrun -c polyrun.yml parallel-rspec --workers 4

# Or run-shards with merge built in:
bin/polyrun -c polyrun.yml run-shards --workers 4 --merge-coverage -- bundle exec rspec

# Merge only (if you ran run-shards without --merge-coverage)
shopt -s nullglob
args=()
for f in coverage/polyrun-fragment-*.json; do args+=(-i "$f"); done
bin/polyrun merge-coverage "${args[@]}" -o coverage/merged.json --format json,lcov,cobertura,console
bin/polyrun report-coverage -i coverage/merged.json -o coverage/out --format json,lcov,cobertura,console
```

Use `--timing polyrun_timing.json` (or `partition.timing_file`) with `cost_binpack` for load-balanced shards—see `cost_balancing/` (`demo.sh` and `demo_rails.sh`). For all strategies with minimal plan examples, see `partition_strategies/`.

## Conventions

- Demos do not include Rails encrypted credentials (`config/credentials.yml.enc` or `config/master.key`). Rails derives a key for dev/test when those files are absent; use `bin/rails credentials:edit` locally if you add real secrets.
- CLI: global flags only work before the subcommand, e.g. `polyrun -c polyrun.yml parallel-rspec …`, not `polyrun parallel-rspec … -c polyrun.yml` (unless `POLYRUN_CONFIG` is set). Same idea for `-v` and `-h`.
- Playwright browsers are not bundled: install with `npx playwright install chromium` or set `PLAYWRIGHT_CLI_EXECUTABLE_PATH`. System specs use Playwright when the CLI exists; otherwise they skip with an install hint (no env flag to force rack_test).
- Polyrun is referenced via `path: "../../.."` in each demo Gemfile (adjust if you move the folder).
- Starter YAML: `polyrun init --list` and `--profile` — see [templates/README.md](templates/README.md) and [docs/SETUP_PROFILE.md](../docs/SETUP_PROFILE.md).

## Quick start (simple)

```bash
cd examples/simple/simple_demo
bundle install
./script/ci_prepare
RAILS_ENV=test bin/rails db:prepare
bundle exec rspec
```

## Prepare all example apps (CI)

```bash
cd examples
chmod +x bin/ci_prepare script/docker_up.sh script/docker_polyrun_provision_demo.sh \
  simple/simple_demo/script/ci_prepare multi_*/multi_demo/script/ci_prepare complex/polyrepo_demo/script/ci_prepare
./bin/ci_prepare
```
