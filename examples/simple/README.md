# Simple example

**`simple_demo`** — Rails 8 app demonstrating **Polyrun** end-to-end: **partition** / **`run-shards`**, **`prepare`**, **`env`** / **`databases`**, **`Polyrun::Coverage::Rails`**, and **merged coverage** after parallel runs.

## Rails data layer

- **Multiple databases** (Rails 8): **`primary`** + **`cache`** with separate SQLite files under `storage/` and `db/cache_migrate/` (same pattern as `examples/multi_database/multi_demo`).
- **Single-process** (no parallel workers): `RAILS_ENV=test bin/rails db:prepare` creates both files.
- **Parallel CI / Postgres**: use `polyrun.yml` → `databases.template_db` + `shard_db_pattern` and `bin/polyrun env` (see `examples/multi_database/README.md` and root README). For SQLite-only parallel tests, give each worker a distinct DB path (e.g. `TEST_ENV_NUMBER` / `POLYRUN_SHARD_INDEX` in `database.yml` ERB) so workers do not share one file.

## Assets and browser tests

- **Propshaft** + `app/assets/stylesheets/application.css` (no Node required for the default flow).
- **RSpec** + **Capybara** + **capybara-playwright-driver** (Chromium). System specs run with **Playwright** when the CLI is detected; otherwise they **skip** (install Playwright per below — do not use a `SKIP_PLAYWRIGHT`-style opt-out).

## Polyrun::Data (fixtures / parallel hooks)

The demo includes **`spec/support/polyrun_parallel_data.rb`** and **`Polyrun::RSpec.install_parallel_provisioning!`** in **`rails_helper`**, plus **`spec/polyrun/polyrun_data_optimizations_spec.rb`** (**`CachedFixtures`**). See **[../fixtures_and_parallel_data.md](../fixtures_and_parallel_data.md)**.

## Spec volume (partition demos)

`lib/demo/lattice/` + `spec/demo/lattice/` — 120 lattice specs (generated; gitignored under `examples/`). `spec/spec_helper.rb` runs the generator before RSpec loads specs; you can also run `ruby examples/script/generate_lattice_spec_suite.rb <demo>` by hand. Keeps **`plan`** / **`run-shards`** / timing demos meaningful.

## Polyrun features used

| Feature | Where |
|--------|--------|
| Coverage fragments | `spec/spec_helper.rb` → `Polyrun::Coverage::Rails.start!`, optional `config/polyrun_coverage.yml` |
| Shard index → fragment name | `POLYRUN_SHARD_INDEX` → `coverage/polyrun-fragment-<shard>.json` |
| Partition + parallel | `polyrun.yml` → `partition.paths_file`, `run-shards` (default strategy: **`round_robin`**; see **[../partition_strategies/README.md](../partition_strategies/README.md)** for others) |
| DB naming for shards | `polyrun.yml` → `databases` (Postgres-style template + pattern) |

## Commands

```bash
cd simple_demo
bundle install
./script/ci_prepare   # once before parallel workers: Propshaft digest marker (Polyrun::Prepare::Assets)
RAILS_ENV=test bin/rails db:prepare

# Serial run (install Playwright first so system specs execute)
bundle exec rspec

# Parallel (4 processes) + merged coverage — built-in (no shell script required):
bundle exec polyrun -c polyrun.yml parallel-rspec --workers 4
# or: chmod +x bin/rspec_parallel && ./bin/rspec_parallel

# Manual: ../../../bin/polyrun -c polyrun.yml run-shards --workers 4 --merge-coverage -- bundle exec rspec
```

Use **`../../../bin/polyrun`** from `simple_demo` (Polyrun gem repo layout) or put `polyrun` on `PATH`.

See **`../README.md`** for the full parallel + merge pattern and **`../TESTING_REQUIREMENTS.md`** for why **`script/ci_prepare`** must not run per shard.

## Playwright setup

```bash
export PLAYWRIGHT_CLI_VERSION=$(bundle exec ruby -e 'require "playwright"; puts Playwright::COMPATIBLE_PLAYWRIGHT_VERSION.strip')
npm install playwright@${PLAYWRIGHT_CLI_VERSION}
npx playwright install chromium
```

Point `PLAYWRIGHT_CLI_EXECUTABLE_PATH` at `npx` or `node_modules/.bin/playwright` if needed.
