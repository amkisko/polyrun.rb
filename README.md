# Polyrun

Ruby gem for parallel test runs, merged coverage (SimpleCov-shaped JSON to JSON, LCOV, Cobertura, or console output), CI reporting (JUnit, timing), and parallel-test hygiene (fixtures, snapshots, per-shard databases, asset preparation). Ship it as one development dependency: no runtime gem dependencies beyond the standard library and vendored code.

## Why?

Running tests in parallel across processes still requires a single merged coverage report, stable shard assignment, isolated databases per worker so rows are not shared, and reliable timing data for cost-based splits—without wiring together many small tools and shell scripts.

Polyrun provides:

- Orchestration: `plan`, `run-shards`, and `parallel-rspec` (run-shards plus merge-coverage), with an optional on-disk queue and constraints for file lists and load balancing.
- Coverage: merge SimpleCov-shaped JSON fragments; emit JSON, LCOV, Cobertura, or console summaries (you can drop separate SimpleCov merge plugins for this path).
- CI reporting: JUnit XML from RSpec JSON; slow-file reports from merged timing JSON.
- Parallel hygiene: asset digest markers, SQL snapshots, YAML fixture batches, and DB URL or shard helpers aligned with `POLYRUN_SHARD_*`.
- No runtime gems in the gemspec: stdlib and vendored pieces only.

Capybara and Playwright stay in your application; Polyrun does not replace browser drivers.

## How?

1. Add the gem (path or RubyGems) and `require "polyrun"` where you integrate—for example coverage merge in CI or prepare hooks.
2. Add a `polyrun.yml` beside the app, or pass `-c` to point at one. Configure `partition` (paths, shard index and total, strategy), and optionally `databases` (Postgres template and `shard_db_pattern`), `prepare`, and `coverage`. If you use `partition.paths_build`, Polyrun can write `partition.paths_file` (for example `spec/spec_paths.txt`) from globs and ordered stages—substring priorities for integration specs, or a regex stage for “Rails-heavy files first”—without a per-project Ruby script. That step runs before `plan` and `run-shards`. Use `bin/polyrun build-paths` to refresh the paths file only.
3. Run prepare once before fan-out—for example `script/ci_prepare` for Vite or webpack builds, and `Polyrun::Prepare::Assets` digest markers. See `examples/TESTING_REQUIREMENTS.md`.
4. Run workers with `bin/polyrun run-shards --workers N -- bundle exec rspec`: N separate OS processes, each running RSpec with its own file list from `partition.paths_file`, or `spec/spec_paths.txt`, or else `spec/**/*_spec.rb`. Stderr shows where paths came from; after a successful multi-worker run it reminds you to run merge-coverage unless you use `parallel-rspec` or `run-shards --merge-coverage`.
5. Merge artifacts with `bin/polyrun merge-coverage` on `coverage/polyrun-fragment-*.json` (one fragment per `POLYRUN_SHARD_INDEX` when coverage is on), or use `bin/polyrun parallel-rspec` or `run-shards --merge-coverage` so Polyrun runs merge for you. Optional: `merge-timing`, `report-timing`, `report-junit`.

Quick CLI samples:

```bash
bin/polyrun version
bin/polyrun build-paths -c polyrun.yml   # write spec/spec_paths.txt from partition.paths_build only
bin/polyrun parallel-rspec --workers 5 -c polyrun.yml   # run-shards + merge-coverage (default: bundle exec rspec)
bin/polyrun run-shards --workers 5 -c polyrun.yml --merge-coverage -- bundle exec rspec
bin/polyrun merge-coverage -i cov1.json -i cov2.json -o merged.json --format json,lcov,cobertura,console
bin/polyrun -c polyrun.yml env --shard 0 --total 4   # print DATABASE_URL-style exports
bin/polyrun init --list
bin/polyrun init --profile gem -o polyrun.yml   # starter YAML; see docs/SETUP_PROFILE.md
```

### Adopting Polyrun (setup profile and scaffolds)

- [docs/SETUP_PROFILE.md](docs/SETUP_PROFILE.md) — Checklist for project type (gem, Rails, Appraisal), parallelism target (one CI job with N workers, matrix shards, or a single non-matrix runner), database layout, prepare, spec order, coverage, and CI model A (single runner with `parallel-rspec`) versus model B (matrix plus a merge-coverage job). Treat `polyrun.yml` as the contract; bin scripts and `database.yml` are adapters.
- `polyrun init` writes a starter `polyrun.yml` or `POLYRUN.md` from built-in templates (`--profile gem`, `rails`, `ci-matrix`, `doc`). Profiles are listed in `examples/templates/README.md`.

Runnable Rails demos (multi-DB, Vite, Capybara, Docker, Postgres sketches) live in `examples/README.md`. For development (tests, RuboCop, Appraisal), see [CONTRIBUTING.md](CONTRIBUTING.md).

---

## Library (after `require "polyrun"`)

| API | Purpose |
|-----|---------|
| `Polyrun::Coverage::Merge` | Merge fragments; formatters for JSON, LCOV, Cobertura, console summary. |
| `Polyrun::Coverage::Collector` | Stdlib `Coverage` → JSON fragment (`POLYRUN_COVERAGE_DISABLE` to skip); `track_under: %w[lib app]`, filters, optional % gate. |
| `Polyrun::Coverage::Reporting` | Write all formats to a directory from a blob or merged JSON file. |
| `Polyrun::Reporting::JUnit` | RSpec `--format json` output or Polyrun testcase JSON → JUnit XML (CI). |
| `Polyrun::Timing::Summary` | Text report of slowest files from merged `polyrun_timing.json`. |
| `Polyrun::Data::Fixtures` | YAML table batches (`each_table`, `load_directory`, optional `apply_insert_all!` with ActiveRecord). |
| `Polyrun::Data::CachedFixtures` | Process-local memoized fixture blocks (AnyFixture-style `register` / `fetch`, stats, `reset!`). |
| `Polyrun::Data::ParallelProvisioning` | Serial vs parallel-worker suite hooks from `POLYRUN_SHARD_*` / `TEST_ENV_NUMBER`. |
| `Polyrun::Data::FactoryInstrumentation` | Opt-in FactoryBot patch → `FactoryCounts` (after `require "factory_bot"`). |
| `Polyrun::Data::SqlSnapshot` | PostgreSQL `pg_dump` / `psql` snapshots under `spec/fixtures/sql_snapshots/`. |
| `Polyrun::Data::FactoryCounts` | Factory/build counters + summary text. |
| `Polyrun::RSpec` (`require "polyrun/rspec"`) | `install_parallel_provisioning!` → `before(:suite)` hooks. |
| `Polyrun::Prepare::Assets` | Digest trees, marker file, `assets:precompile`. |
| `Polyrun::Database::Shard` | Shard env map, `%{shard}` DB names, Postgres URL suffix. |

## Development

```bash
bundle install
bundle exec rake spec
bundle exec rake ci   # RSpec + RuboCop
```

Tests include subprocess CLI coverage (`spec/polyrun/cli_spec.rb`: merge-coverage across formats, merge-timing, report-junit, report-timing, plan, env with `databases:`, prepare, report-coverage, db:* dry-run and errors) and unit specs for `Coverage::Merge`, `Timing::Merge`, `Timing::Summary`, `Reporting::JUnit`, `Partition::Plan`, `Database::UrlBuilder` and `Shard`, `Prepare::Artifacts`, `Data::*`, `Env::Ci`, `Queue::FileStore`, and `SqlSnapshot` (with `Open3` stubbed for `pg_dump`).

Merge performance defaults align with `spec/polyrun/coverage/merge_scale_spec.rb` (~110 files × 310 lines per fragment):

```bash
ruby benchmark/merge_coverage.rb
bundle exec rake bench_merge
# MERGE_FRAGMENTS=16 MERGE_REPS=2 ruby benchmark/merge_coverage.rb
```

The script benchmarks `merge_two`, balanced `merge_blob_tree` (same reduction as `merge-coverage` / `merge_files`), a naive left-fold, JSON on disk via `merge_files`, and `merge_fragments` with `meta` and `polyrun_coverage_groups` (group recomputation).

Merge is JSON aggregation over coverage fragments; for typical apps it stays well under one second. If merge exceeds ten seconds, Polyrun prints a warning on stderr (override with `POLYRUN_MERGE_SLOW_WARN_SECONDS`; set to `0` to disable).

## CLI (reference)

```bash
bin/polyrun plan --total 2 --shard 0 a.rb b.rb c.rb
bin/polyrun plan --total 3 --shard 0 --timing polyrun_timing.json --paths-file spec/spec_paths.txt
bin/polyrun plan --strategy hrw --total 4 --shard 0 --paths-file spec/spec_paths.txt
bin/polyrun queue init --paths-file spec/spec_paths.txt --timing polyrun_timing.json --dir .polyrun-queue
bin/polyrun report-coverage -i merged.json -o coverage/out --format json,lcov,cobertura,console
bin/polyrun report-junit -i rspec.json -o junit.xml
bin/polyrun report-timing -i polyrun_timing.json --top 20
bin/polyrun -c polyrun.yml plan --shard 0 --total 4
bin/polyrun -c polyrun.yml prepare --recipe assets --dry-run
bin/polyrun parallel-rspec --workers 4 -c polyrun.yml
```

`polyrun.yml` can set `partition.*`, `prepare.recipe` (`default` or `assets`), `prepare.rails_root`, and related keys. `POLYRUN_SHARD_*` overrides configuration where documented; CLI flags override environment variables.

Shard index and total in CI (`Polyrun::Env::Ci`): when set, `POLYRUN_SHARD_INDEX` and `POLYRUN_SHARD_TOTAL` take precedence. Otherwise `CI_NODE_INDEX` and `CI_NODE_TOTAL` apply when `CI` is set (GitLab defines these; the code is not GitLab-specific), along with Buildkite and Circle CI variables. GitHub Actions does not set `CI_NODE_*` by default—set `POLYRUN_*` from the job matrix.

File queue (`polyrun queue …`): batches live on disk under a lock file; paths move from `pending` to `leases` on claim and to `done` on ack. There is no lease TTL: if a worker dies after claiming, paths remain in `leases` until you recover them (manually or with a future reclaim command).

## Examples

See [`examples/README.md`](examples/README.md) for Rails apps (Capybara, Playwright, Vite, multi-database, Docker Compose, polyrepo). Parallel CI practices: [`examples/TESTING_REQUIREMENTS.md`](examples/TESTING_REQUIREMENTS.md). Behavioral contracts: `spec/polyrun/mandatory_parallel_support_spec.rb`.

You can replace SimpleCov and simplecov plugins, parallel_tests, and rspec_junit_formatter with Polyrun for those roles. TestProf-style workflows can use `merge-timing`, `report-timing`, and `Data::FactoryCounts` (optionally with `Data::FactoryInstrumentation`). Oaken-style YAML and bulk-insert patterns can use `Data::Fixtures` and `ParallelProvisioning` for shard-aware seeding; the Oaken Ruby DSL is not replicated—wire your own `truncate` and `load_seed` in hooks.

---

Sponsored by [Kisko Labs](https://www.kiskolabs.com).

<a href="https://www.kiskolabs.com">
  <img src="kisko.svg" width="200" alt="Sponsored by Kisko Labs" />
</a>
