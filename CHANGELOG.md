# CHANGELOG

## Unreleased

## 1.5.0 (2026-05-04)

- Add `run-shards --worker-timeout SEC` and `POLYRUN_WORKER_TIMEOUT_SEC` (wall time per worker since spawn); stop stuck workers; record exit 124 for that shard.
- Add `run-shards --worker-idle-timeout SEC` and `POLYRUN_WORKER_IDLE_TIMEOUT_SEC`; parent reads monotonic timestamps from `POLYRUN_WORKER_PING_FILE`; record exit 125 when the last ping is stale. Idle applies only after a valid positive ping (use wall timeout until the first ping).
- Add `Polyrun::WorkerPing` (`ping!`, `ensure_interval_ping_thread!` when `POLYRUN_WORKER_PING_THREAD`). Add `Polyrun::RSpec.install_worker_ping!` and `Polyrun::Minitest.install_worker_ping!`; Polyrun Quick calls `WorkerPing.ping!` around each example. Parent creates ping paths under `tmp/polyrun/` and unlinks files after workers exit.
- Poll every live shard worker together when timeouts are enabled so idle and wall limits apply to all children, not only the first waiter.
- Split parallel worker teardown into `RunShardsParallelWait` and `RunShardsWorkerInterrupt`; keep spawn logic in `RunShardsParallelChildren`.
- Add `Polyrun::Log.orchestration_warn`; when `POLYRUN_ORCHESTRATION_STDERR=1`, copy one line to process `$stderr` if `Log.stderr` is not the same object (custom/null sinks).
- Wire `env_worker_timeout_sec` / `env_worker_idle_timeout_sec` into `ci-shard-run` plan context. Rescue `Interrupt` around `after_suite` in `run-shards` and `ci-shard` orchestration where suite hooks run.
- In `Polyrun::Hooks#run_phase`, rescue `Interrupt` for Ruby DSL and shell hook phases (return 130).
- Document worker timeout, idle ping, and `POLYRUN_ORCHESTRATION_STDERR` in `polyrun help`. Add `sig/polyrun/worker_ping.rbs` and extend `Polyrun::RSpec` / `Polyrun::Minitest` installer signatures.

## 1.4.2 (2026-04-24)

- Add richer HTML coverage reports: summary cards, group coverage, sortable file tables, project-relative paths, and per-file source detail.
- Refactor HTML coverage rendering into stdlib `ERB` templates with `_*.html.erb` partials and isolated `report.css` / `report.js` assets; inline assets into final standalone report.
- Fix `track_files` coverage scope in `Collector.finish`: keep only files matched by tracked globs, drop unrelated loaded runtime files, and add unloaded tracked files only for non-sharded runs.
- Add coverage specs for divergent `track_under` / `track_files` configs in serial and sharded finish paths; add `TrackFiles.keep_tracked_files`.

## 1.4.1 (2026-04-16)

- Add `polyrun merge-failures` and `run-shards --merge-failures` / `--merge-failures-output` / `--merge-failures-format`; merge per-worker JSONL under `tmp/polyrun_failures/polyrun-failure-fragment-*.jsonl` (or RSpec JSON via `-i`). Run merge after all workers exit, including when a shard failed (`--merge-coverage` still runs only after all shards succeed).
- Add `Polyrun::Reporting::FailureMerge`, `Polyrun::RSpec.install_failure_fragments!`, and `Polyrun::Reporting::RspecFailureFragmentFormatter`; parent sets `POLYRUN_FAILURE_FRAGMENTS=1` on workers when merge-failures is enabled.
- Add optional `reporting:` in `polyrun.yml` and `Polyrun::Config#reporting` for merge-failures toggles and paths; honor `POLYRUN_MERGE_FAILURES`, `POLYRUN_MERGED_FAILURES_OUT`, `POLYRUN_MERGED_FAILURES_FORMAT`; set `POLYRUN_MERGED_FAILURES_PATH` for `after_suite` when merge wrote a file.
- On bad JSONL or non-RSpec JSON, raise `Polyrun::Error` with path and line where applicable; `merge-failures` exits 1 without a full stack trace; a failed merge after successful workers forces `run-shards` exit 1.
- Fix `run_shards_plan_ready_log` to take `cfg` so debug logging for merge-failures does not raise `NameError`.

## 1.4.0 (2026-04-16)

- Add `hooks:` in `polyrun.yml` — shell commands for `before_suite` / `after_suite`, `before_shard` / `after_shard`, `before_worker` / `after_worker` (RSpec-style YAML keys `before(:suite)`, `before(:all)`, `before(:each)` accepted). Wire hooks into `run-shards`, `parallel-rspec`, and `ci-shard-*`.
- Add `hooks.ruby` / `hooks.ruby_file` and `Polyrun::Hooks::Dsl` (`before(:suite)` … `after(:each)` blocks); worker Ruby hooks run in the child via `ruby -e` + `POLYRUN_HOOKS_RUBY_FILE`.
- Add `polyrun hook run <phase>` (`--shard` / `--total` optional). Set `POLYRUN_HOOKS_DISABLE=1` to skip hooks during orchestration only; `hook run` still executes.
- On `ci-shard-run` / `ci-shard-rspec`, skip automatic `before_suite` / `after_suite` when `POLYRUN_SHARD_TOTAL` > 1 (matrix); run suite hooks once via `polyrun hook run` or set `POLYRUN_HOOKS_SUITE_PER_MATRIX_JOB=1` to run them on every matrix job.
- Document hook phases, matrix vs suite, and `after_shard` ordering in `README.md`; list `Polyrun::Hooks` and `Polyrun::Hooks::Dsl` in the library section.

## 1.3.0 (2026-04-15)

- Add safe parsing for `ci-shard-run` / `ci-shard-rspec` `--shard-processes` and `--workers` (warn + exit 2 on missing or non-integer values).
- Fix `shard_child_env` when `matrix_total > 1` and `matrix_index` is nil: omit `POLYRUN_SHARD_MATRIX_*` and warn (avoid `Integer(nil)`).
- Document in `polyrun help` that `POLYRUN_SHARD_PROCESSES` and ci-shard `--workers` / `--shard-processes` are local processes per matrix job, distinct from `POLYRUN_WORKERS` / `run-shards`.
- BREAKING: Multi-worker shard runs may emit coverage JSON fragments whose basenames include `shard*` and `worker*` segments; `merge-coverage` still matches `polyrun-fragment-*.json`.

## 1.2.0 (2026-04-15)

- Add `polyrun config <dotted.path>` to print values from `Polyrun::Config::Effective` (same effective tree as runtime: arbitrary YAML paths, merged `prepare.env.<KEY>` as for `polyrun prepare`, resolved `partition.shard_index`, `partition.shard_total`, `partition.timing_granularity`, and `workers`).
- Memoize `Polyrun::Config::Effective.build` per thread (keyed by config path, object id, and env fingerprint) so repeated `dig` calls do not rebuild the merged tree.
- Add `DISPATCH_SUBCOMMAND_NAMES` and `IMPLICIT_PATH_EXCLUSION_TOKENS`; route implicit path-only argv against one list (includes `ci-shard-*`, `help`, `version`); add spec that dispatch names match `when` branches in `lib/polyrun/cli.rb`.
- Run `polyrun` with no subcommand to fan out parallel tests: pick RSpec (`start`), Minitest (`bundle exec rails test` or `bundle exec ruby -I test`), or Polyrun Quick (`bundle exec polyrun quick`) from `spec/**/*_spec.rb` vs `test/**/*_test.rb` vs Quick globs.
- Accept path-only argv (and optional `run-shards` options before paths, e.g. `--workers`) to shard those files without naming a subcommand; infer suite from `_spec.rb` / `_test.rb` vs other `.rb` files.
- Add optional `partition.suite` (`auto`, `rspec`, `minitest`, `quick`) when resolving globbed paths for `run-shards` / `parallel-rspec` / default runs.
- Document implicit argv (known subcommand first vs path-like implicit parallel) and parallel Quick `bundle exec` from app root in `polyrun help` and `examples/README.md`.
- Comment `detect_auto_suite` glob order in `lib/polyrun/partition/paths.rb` (RSpec/Minitest globs before Quick discovery).
- Remove redundant `OptionParser` from `polyrun config` (no options; banner only).

## 1.1.0 (2026-04-15)

- Add `ci-shard-run` / `ci-shard-rspec` for matrix-style sharding (one job per `POLYRUN_SHARD_INDEX` / `POLYRUN_SHARD_TOTAL`): resolve paths via the same plan as `polyrun plan`, then `exec` the given command with this shard’s paths (unlike `run-shards`, which fans out multiple workers on one host).
- Add experimental per-example partition timing: `partition.timing_granularity` / `--timing-granularity` (`file` default, `example` for `path:line` items), `POLYRUN_TIMING_GRANULARITY`, merged timing JSON with `absolute_path:line` keys, `TimingKeys.load_costs_json_file`, constraints matching pins/globs on the file part of locators, queue init support, and optional `Polyrun::Timing::RSpecExampleFormatter` plus `Polyrun::RSpec.install_example_timing!`.
- Add `Polyrun::ProcessStdio.inherit_stdio_spawn_wait` and `spawn_wait` for subprocesses with inherited stdio (or temp-file capture when `silent: true`) to avoid Open3 pipe-thread noise on interrupt; used by prepare (shell / custom assets), `Prepare::Assets.precompile!`, and `Provision.prepare_template!` (`bin/rails db:prepare`). On failure, `db:prepare` / `assets:precompile` embed captured stdout/stderr in `Polyrun::Error` (truncated when huge).
- Refactor `polyrun plan` around `plan_command_compute_manifest` and `plan_command_build_manifest`; `cmd_plan` output stays aligned with `plan_command_compute_manifest` (tests guard drift).
- `TimingKeys.load_costs_json_file` accepts optional `root:` for key normalization; warns when two JSON keys normalize to the same entry with different seconds; `TimingKeys.canonical_file_path` / `normalize_locator` resolve directory symlinks so `/var/…` and `/private/var/…` (macOS) map to one key.
- `Polyrun::RSpec.install_example_timing!(output_path:)` no longer sets `ENV` when an explicit path is passed; formatter uses `timing_output_path` (override or `ENV` / default filename).
- Fix noisy `IOError` / broken-pipe behavior when interrupting long-running prepare / Rails subprocesses that previously used `Open3.capture3`.

## 1.0.0 (2026-04-14)

- Initial stable release of Polyrun: parallel tests, SimpleCov-compatible coverage formatters, fixtures/snapshots, assets and DB provisioning with zero runtime gem dependencies.
- Add `polyrun` CLI with `plan`, `run-shards`, partition/load balancing, coverage merge and reporting, database helpers, queue helpers, and the Quick runner.
- Add coverage Rake tasks and YAML configuration for merged / Cobertura-style output.
- Add database command flows using `db:prepare` (replacing earlier `db:migrate`-only paths) for provisioning-style runs.
- Implement graceful shutdown for worker processes in `run_shards` when the parent is interrupted.
- Expand Quick runner defaults and parallel shard database creation.
- Add examples tree, specs for merge and queue behavior, and docs for cwd-relative configuration.
- Add RSpec suite, RuboCop (including a FileLength cop), YAML templates, and a `bin/release` script.
- Add RBS signatures under `sig/` and validate them in CI; expand documentation and specs.
