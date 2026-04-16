# Polyrun

Ruby gem for parallel test runs, merged coverage (SimpleCov-compatible JSON to JSON, LCOV, Cobertura, or console output), CI reporting (JUnit, timing), and parallel-test hygiene (fixtures, snapshots, per-shard databases, asset preparation). Ship it as one development dependency: no runtime gem dependencies beyond the standard library and vendored code.

## Why?

Running tests in parallel across processes still requires a single merged coverage report, stable shard assignment, isolated databases per worker so rows are not shared, and reliable timing data for cost-based splits—without wiring together many small tools and shell scripts.

Polyrun provides:

- Orchestration: `plan`, `run-shards`, and `parallel-rspec` (run-shards plus merge-coverage), with an optional on-disk queue and constraints for file lists and load balancing. For **GitHub Actions-style matrix sharding** (one job per global shard), use `ci-shard-run -- …` (any test runner) or `ci-shard-rspec`—not `run-shards` / `parallel-rspec`, which fan out N workers on one machine.
- Coverage: merge SimpleCov-compatible JSON fragments; emit JSON, LCOV, Cobertura, or console summaries (you can drop separate SimpleCov merge plugins for this path).
- CI reporting: JUnit XML from RSpec JSON; slow-file reports from merged timing JSON.
- Parallel hygiene: asset digest markers, SQL snapshots, YAML fixture batches, and DB URL or shard helpers aligned with `POLYRUN_SHARD_*`.
- Optional **`polyrun quick`**: `Polyrun::Quick` — nested `describe`, `it` / `test`, `before` / `after`, `let` / `let!`, `expect(x).to …` matchers, `assert_*` (Minitest-like), and optional **`Polyrun::Quick.capybara!`** (extends `Capybara::DSL` when the **capybara** gem is loaded). Stdlib-only in Polyrun itself. Coverage uses the same `Polyrun::Coverage::Collector` path as RSpec when `POLYRUN_COVERAGE=1` or `config/polyrun_coverage.yml` is present (not when `POLYRUN_COVERAGE_DISABLE=1`).
- No runtime gems in the gemspec: stdlib and vendored pieces only.

Capybara and Playwright stay in your application; Polyrun does not replace browser drivers.

## How?

1. Add the gem (path or RubyGems) and `require "polyrun"` where you integrate—for example coverage merge in CI or prepare hooks. To pin the executable in your app, run `bundle binstubs polyrun` (writes `bin/polyrun`; ensure `bin/` is on `PATH` or invoke `./bin/polyrun`).
2. Add a `polyrun.yml` beside the app, or pass `-c` to point at one. Configure `partition` (paths, shard index and total, strategy), and optionally `databases` (Postgres template and `shard_db_pattern`), `prepare`, and `coverage`. If you use `partition.paths_build`, Polyrun can write `partition.paths_file` (for example `spec/spec_paths.txt`) from globs and ordered stages—substring priorities for integration specs, or a regex stage for “Rails-heavy files first”—without a per-project Ruby script. That step runs before `plan` and `run-shards`. Use `bin/polyrun build-paths` to refresh the paths file only.
3. Run prepare once before fan-out—for example `script/ci_prepare` for Vite or webpack builds, and `Polyrun::Prepare::Assets` digest markers. See `examples/TESTING_REQUIREMENTS.md`.
4. Run workers with `bin/polyrun run-shards --workers N -- bundle exec rspec`: N separate OS processes, each running RSpec with its own file list from `partition.paths_file`, or `spec/spec_paths.txt`, or else `spec/**/*_spec.rb`. Stderr shows where paths came from; after a successful multi-worker run it reminds you to run merge-coverage unless you use `parallel-rspec` or `run-shards --merge-coverage`.
5. Merge artifacts with `bin/polyrun merge-coverage` on `coverage/polyrun-fragment-*.json` (one fragment per `POLYRUN_SHARD_INDEX` when coverage is on), or use `bin/polyrun parallel-rspec` or `run-shards --merge-coverage` so Polyrun runs merge for you. Optional: `merge-timing`, `report-timing`, `report-junit`.

### Hooks (`hooks:` in `polyrun.yml`)

Optional **shell** commands and/or a **Ruby DSL** file for instrumentation (telemetry, Slack, logging, manual debugging). Names mirror RSpec’s API (`before(:suite)`, `before(:all)`, `before(:each)`), but **Polyrun hooks are about process orchestration**, not RSpec example groups. Below, **suite / shard / worker** mean Polyrun’s model unless stated otherwise.

#### What “suite”, “shard”, and “worker” mean

| Term | Process | Meaning |
|------|---------|---------|
| **Suite** | **Parent** only | One **orchestration run** on a single machine: a single `polyrun run-shards` / `parallel-rspec` / `ci-shard-run` (with **one** global shard, see below). `before_suite` runs once before any worker is started; `after_suite` runs once after all workers have exited and (when used) merge-coverage has finished. This is **not** the same as “the whole RSpec suite in one process”—with `--workers N`, RSpec runs in **N separate processes**, each with its own examples. |
| **Shard** | **Parent** only | One **partition** of the path list for this run, identified by `POLYRUN_SHARD_INDEX` / `POLYRUN_SHARD_TOTAL` **for that parallel layout** (0 … N−1 for `run-shards` with N workers). `before_shard` runs in the parent **immediately before** `Process.spawn` for that index; `after_shard` runs **after** that child has exited. The parent **waits workers in shard index order** (0, then 1, …), so `after_shard` runs in that order—not in “who finished first” order if workers overlap in time. Empty partitions are skipped (no spawn, no hooks). |
| **Worker** | **Child** OS process | The process that runs your command after `--` (e.g. `bundle exec rspec …`). `before_worker` / `after_worker` run **in that child**, directly before and after the test command. **Individual examples run only after `before_worker` completes** (inside the same process as RSpec/Minitest). |

**CI matrix** (`POLYRUN_SHARD_TOTAL` > 1, one job per index): each job is a **global shard**, not a full “suite” in the pipeline sense. **`ci-shard-run` / `ci-shard-rspec` with one process per job do not run `before_suite` / `after_suite` automatically**—otherwise they would run once per matrix cell. Put pipeline-wide setup/teardown in a **separate CI step** (e.g. `bin/polyrun hook run before_suite` and `hook run after_suite` once), or set `POLYRUN_HOOKS_SUITE_PER_MATRIX_JOB=1` to restore the old behaviour (suite hooks on every matrix job). **`before_shard` / `after_shard` / worker hooks still run** per job, with `POLYRUN_SHARD_INDEX` / `POLYRUN_SHARD_TOTAL` set from the matrix. A **single** non-matrix `ci-shard-run` (`POLYRUN_SHARD_TOTAL` is 1) still runs suite hooks like `run-shards --workers 1`. Fan-out on one host (`--shard-processes` > 1) still runs **`before_suite` / `after_suite` once** for that job, around the local workers.

#### Lifecycle (typical `run-shards` with multiple workers)

```text
[Parent]  before_suite
[Parent]  for each shard index i that has paths:
            before_shard(i) → spawn worker i
[Child i] before_worker →  test runner starts → examples run → runner exits
[Parent]  after_shard(i)   (parent waits children in shard index order 0…N−1, not global finish order)
[Parent]  merge-coverage (if requested)
[Parent]  after_suite
```

`after_worker` runs in the child after the test command exits, before the parent’s `after_shard`.

#### Order and priority within one phase

1. **Ruby DSL, then shell (YAML)** — For the same phase (e.g. `before_suite`), all **Ruby** blocks from `hooks.ruby` run first, then every **shell** command from YAML for that phase.
2. **Multiple Ruby blocks** — In one DSL file, registrations run in **source order** (e.g. two `before(:suite)` blocks run top to bottom).
3. **Multiple shell commands** — Use a **YAML list**; entries run in list order:
   ```yaml
   before_suite:
     - echo first
     - echo second
   ```
4. **Duplicate YAML keys** — Do **not** repeat the same key (e.g. two `before_suite:` lines). Parsers may keep only one value; behaviour is undefined. Prefer a **list** under a single key.
5. **Failure** — If any step in a phase fails (non-zero exit from shell; uncaught error in Ruby), orchestration stops or marks failure per existing `run-shards` rules; `after_worker` shell steps use `|| true` so a failing teardown does not mask the test exit code (Ruby `after_worker` is wrapped similarly in the worker script).

Environment includes `POLYRUN_HOOK_PHASE`, `POLYRUN_HOOK=1`, `POLYRUN_HOOK_ORCHESTRATOR` (`1` in parent, `0` in workers), `POLYRUN_SHARD_*`, and `POLYRUN_SUITE_EXIT_STATUS` on `after_suite`. Worker children get `POLYRUN_HOOKS_RUBY_FILE` when using the Ruby DSL. Set `POLYRUN_HOOKS_DISABLE=1` to skip hooks during `run-shards` / `parallel-rspec` / `ci-shard-*` (orchestration only); `polyrun hook run` still executes hooks. **`POLYRUN_HOOKS_SUITE_PER_MATRIX_JOB=1`** — when set, run `before_suite` / `after_suite` on every CI matrix job (not recommended for expensive global setup).

**YAML keys (shell) and RSpec-style names in YAML:**

| YAML key | DSL in `hooks.ruby` | When |
|----------|----------------------|------|
| `before_suite` / `after_suite` | `before(:suite)` / `after(:suite)` | Parent: once per orchestration on one host; **skipped** for `ci-shard-run` when `POLYRUN_SHARD_TOTAL` > 1 unless `POLYRUN_HOOKS_SUITE_PER_MATRIX_JOB=1` (see matrix paragraph above) |
| `before_shard` / `after_shard` | `before(:all)` / `after(:all)` | Parent: per shard index (spawn / after exit) |
| `before_worker` / `after_worker` | `before(:each)` / `after(:each)` | Child: around the test command |

**Ruby DSL (`hooks.ruby` or `hooks.ruby_file`):** path to a `.rb` file (relative to the project root). Blocks receive a `Hash` with **string keys** (same env as shell hooks). Worker-phase Ruby hooks run in the child via `ruby -e 'require "polyrun"; …'`.

Run one phase by hand: `bin/polyrun hook run before_suite` (optional `--shard N --total M`). YAML may use quoted keys such as `"before(:suite)"` instead of `before_suite`.

Quick CLI samples:

If the current directory already has `polyrun.yml` or `config/polyrun.yml`, you can omit `-c` (same as `Config.load` default discovery). Pass `-c PATH` or set `POLYRUN_CONFIG` when the file lives elsewhere or uses another name.

```bash
bin/polyrun version
bin/polyrun build-paths   # write spec/spec_paths.txt from partition.paths_build (uses polyrun.yml in cwd)
bin/polyrun ci-shard-run -- bundle exec rspec   # CI matrix: shard plan + append paths to the command after --
bin/polyrun ci-shard-rspec   # same as ci-shard-run -- bundle exec rspec
bin/polyrun parallel-rspec --workers 5   # run-shards + merge-coverage (default: bundle exec rspec)
bin/polyrun run-shards --workers 5 --merge-coverage -- bundle exec rspec
bin/polyrun merge-coverage -i cov1.json -i cov2.json -o merged.json --format json,lcov,cobertura,console
bin/polyrun env --shard 0 --total 4   # print DATABASE_URL exports from polyrun.yml in cwd
bin/polyrun init --list
bin/polyrun init --profile gem -o polyrun.yml   # starter YAML; see docs/SETUP_PROFILE.md
bin/polyrun quick   # Polyrun::Quick examples under spec/polyrun_quick/ or test/polyrun_quick/
bin/polyrun hook run before_suite   # run hooks.before_suite from polyrun.yml (manual / CI)
```

### Matrix shards and timing

- `ci-shard-run` — Pass the command as separate words after `--` (e.g. `ci-shard-run -- bundle exec rspec`). One combined string with spaces is split via `Shellwords`, not a full shell; shell-only quoting does not apply.
- Timing JSON — Run `plan`, `queue init`, and `merge-timing` from the same repository root (cwd) you use when producing `polyrun_timing.json` so path keys normalize consistently. `Polyrun::Partition::Plan.load_timing_costs` and `TimingKeys.load_costs_json_file` accept `root:` to align keys to a fixed directory.
- Per-example timing (`--timing-granularity example`) — Experimental. Cost maps and plan items scale with example count, not file count; expect larger memory use and slower planning than file mode on big suites.

### Adopting Polyrun (setup profile and scaffolds)

- [docs/SETUP_PROFILE.md](docs/SETUP_PROFILE.md) — Checklist for project type (gem, Rails, Appraisal), parallelism target (one CI job with N workers, matrix shards, or a single non-matrix runner), database layout, prepare, spec order, coverage, and CI model A (single runner with `parallel-rspec`) versus model B (matrix plus a merge-coverage job). Treat `polyrun.yml` as the contract; bin scripts and `database.yml` are adapters.
- `polyrun init` writes a starter `polyrun.yml` or `POLYRUN.md` from built-in templates (`--profile gem`, `rails`, `ci-matrix`, `doc`). Profiles are listed in `examples/templates/README.md`.

Runnable Rails demos (multi-DB, Vite, Capybara, Docker, Postgres sketches) live in `examples/README.md`. For development (tests, RuboCop, Appraisal), see [CONTRIBUTING.md](CONTRIBUTING.md).

---

## Library (after `require "polyrun"`)

That single require loads the CLI and core library **without** loading RSpec or Minitest. Optional integrations (use only what your app needs):

- `require "polyrun/rspec"` — `Polyrun::RSpec` registers `ParallelProvisioning` in `before(:suite)` (your app must use RSpec).
- `require "polyrun/minitest"` — `Polyrun::Minitest` is a thin alias for `ParallelProvisioning.run_suite_hooks!` (does not `require "minitest"`).
- `require "polyrun/reporting/rspec_junit"` — `Polyrun::Reporting::RspecJunit` adds RSpec’s JSON formatter and writes JUnit on exit; RSpec is loaded only inside `RspecJunit.install!`.

| API | Purpose |
|-----|---------|
| `Polyrun::Quick` (`require "polyrun/quick"`) | Nested `describe`; `it` / `test`; `before` / `after`; `let` / `let!`; `expect(x).to eq` / `be_truthy` / `be_falsey` / `match` / `include`; `assert_*`. Call `Polyrun::Quick.capybara!` after `require "capybara"` (and configure `Capybara.app` in your app) to use `visit`, `page`, etc. Run: `polyrun quick` (defaults: `spec/polyrun_quick/**/*.rb`, `test/polyrun_quick/**/*.rb`). |
| `Polyrun::Log` | Swappable stderr/stdout for all CLI and library messages. Set `Polyrun.stderr` / `Polyrun.stdout` (or `Polyrun::Log.stderr` / `stdout`) to an `IO`, `StringIO`, or Ruby `Logger`. `Polyrun::Log.reset_io!` clears custom sinks. |
| `Polyrun::Coverage::Merge` | Merge fragments; formatters for JSON, LCOV, Cobertura, console summary. |
| `Polyrun::Coverage::Collector` | Stdlib `Coverage` → JSON fragment (`POLYRUN_COVERAGE_DISABLE` to skip); `track_under: %w[lib app]`, filters, optional % gate. |
| `Polyrun::Coverage::Reporting` | Write all formats to a directory from a blob or merged JSON file. |
| `Polyrun::Reporting::JUnit` | RSpec `--format json` output or Polyrun testcase JSON → JUnit XML (CI). For RSpec formatter wiring see `Polyrun::Reporting::RspecJunit` (`require "polyrun/reporting/rspec_junit"`). |
| `Polyrun::Timing::Summary` | Text report of slowest files from merged `polyrun_timing.json`. |
| `Polyrun::Data::Fixtures` | YAML table batches (`each_table`, `load_directory`, optional `apply_insert_all!` with ActiveRecord). |
| `Polyrun::Data::CachedFixtures` | Process-local memoized fixture blocks (`register` / `fetch`, stats, `reset!`). |
| `Polyrun::Data::ParallelProvisioning` | Serial vs parallel-worker suite hooks from `POLYRUN_SHARD_*` / `TEST_ENV_NUMBER`. |
| `Polyrun::Data::FactoryInstrumentation` | Opt-in FactoryBot patch → `FactoryCounts` (after `require "factory_bot"`). |
| `Polyrun::Data::SqlSnapshot` | PostgreSQL `pg_dump` / `psql` snapshots under `spec/fixtures/sql_snapshots/`. |
| `Polyrun::Data::FactoryCounts` | Factory/build counters + summary text. |
| `Polyrun::RSpec` (`require "polyrun/rspec"`) | `install_parallel_provisioning!` → `before(:suite)` hooks. |
| `Polyrun::Minitest` (`require "polyrun/minitest"`) | `install_parallel_provisioning!` → same as `ParallelProvisioning.run_suite_hooks!` (no Minitest gem dependency). |
| `Polyrun::Reporting::RspecJunit` (`require "polyrun/reporting/rspec_junit"`) | CI: RSpec JSON formatter + JUnit from `install!` (RSpec loaded only there). |
| `Polyrun::Prepare::Assets` | Digest trees, marker file, `assets:precompile`. |
| `Polyrun::Database::Shard` | Shard env map, `%{shard}` DB names, URL path suffix for `postgres://`, `mysql2://`, `mongodb://`, etc. |
| `Polyrun::Database::UrlBuilder` | URLs from `polyrun.yml` `databases:` — nested blocks or `adapter:` for common Rails stacks (`postgresql`, `mysql`/`mysql2`, `trilogy`, `sqlserver`/`mssql`, `sqlite3`/`sqlite`, `mongodb`/`mongo`). |
| `Polyrun::Hooks` | Load from `Config#hooks`; `run_phase` / `run_phase_if_enabled`; `build_worker_shell_script` wraps the worker command. |
| `Polyrun::Hooks::Dsl` | Ruby hook file (`hooks.ruby`); `before(:suite)` / `after(:each)` etc. in `config/polyrun_hooks.rb` (see README). |

## Development

```bash
bundle install
bundle exec rake spec
bundle exec rake rbs   # optional: validate RBS in sig/
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
bin/polyrun plan --shard 0 --total 4   # polyrun.yml in cwd
bin/polyrun prepare --recipe assets --dry-run
bin/polyrun parallel-rspec --workers 4
bin/polyrun quick spec/polyrun_quick/smoke.rb
```

`polyrun.yml` can set `partition.*`, `prepare.recipe` (`default` or `assets`), `prepare.rails_root`, and related keys. `POLYRUN_SHARD_*` overrides configuration where documented; CLI flags override environment variables.

Shard index and total in CI (`Polyrun::Env::Ci`): when set, `POLYRUN_SHARD_INDEX` and `POLYRUN_SHARD_TOTAL` take precedence. When `CI` is truthy, `CI_NODE_INDEX` / `CI_NODE_TOTAL` and other parallel-job environment variables are read if present. If your runner does not export those, set `POLYRUN_SHARD_*` from the job matrix.

File queue (`polyrun queue …`): batches live on disk under a lock file; paths move from `pending` to `leases` on claim and to `done` on ack. There is no lease TTL: if a worker dies after claiming, paths remain in `leases` until you recover them (manually or with a future reclaim command).

## Examples

See [`examples/README.md`](examples/README.md) for Rails apps (Capybara, Playwright, Vite, multi-database, Docker Compose, polyrepo). Parallel CI practices: [`examples/TESTING_REQUIREMENTS.md`](examples/TESTING_REQUIREMENTS.md). Behavioral contracts: `spec/polyrun/mandatory_parallel_support_spec.rb`.

You can replace SimpleCov and simplecov plugins, parallel_tests, and rspec_junit_formatter with Polyrun for those roles. Use `merge-timing`, `report-timing`, and `Data::FactoryCounts` (optionally with `Data::FactoryInstrumentation`) for slow-file and factory metrics. YAML fixture batches and bulk inserts can use `Data::Fixtures` and `ParallelProvisioning` for shard-aware seeding; wire your own `truncate` and `load_seed` in hooks.

## License

Released under the [MIT License](LICENSE). Copyright (c) 2026 Andrei Makarov.

## Contributing

Bug reports and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, tests, RuboCop, RBS, optional Trunk, and PR conventions. Community participation follows [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## Security

Do not open public issues for security vulnerabilities. See [SECURITY.md](SECURITY.md) for how to report them.

## Sponsors

Sponsored by [Kisko Labs](https://www.kiskolabs.com).

<a href="https://www.kiskolabs.com">
  <img src="kisko.svg" width="200" alt="Sponsored by Kisko Labs" />
</a>
