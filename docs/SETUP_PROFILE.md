# Polyrun setup profile (agent / human checklist)

Use this as a fill-in worksheet before editing a host project. `polyrun.yml` is the contract; everything else is an adapter that must stay aligned with it.

## 1. Project shape

| Field | Options / notes |
|--------|------------------|
| Project type | Gem (library, no Rails app), Rails (full app), or multi-gemfile (Appraisal / multiple `gemfiles/*.gemfile`) |
| Gemfile path to polyrun | For example `gem "polyrun", path: "../polyrun.rb"` or `gem "polyrun"` from RubyGems—note the path relative to each gemfile |
| Appraisal / Docker | If Appraisal: polyrun must appear in `Appraisals` and each generated gemfile. If Docker: document working directory and whether prepare is one-shot or repeated with tests |

## 2. Parallelism target (pick one primary story)

| Target | Typical CLI / CI |
|--------|-------------------|
| Single CI job, N workers on one runner | One workflow job runs `polyrun parallel-rspec --workers N` (or `start`); merge coverage in the same job or a small follow-up step; upload artifacts |
| Matrix: one shard per CI job | Matrix sets `POLYRUN_SHARD_INDEX` / `POLYRUN_SHARD_TOTAL` (or CI vendor equivalents—see `Polyrun::Env::Ci` and the README); each job runs `plan` plus the test command for its shard; upload `coverage/polyrun-fragment-<i>.json`; a merge job runs `merge-coverage` |

Do not mix “fan out N workers inside one job” with “matrix shard index” in the same workflow without a clear story for which process writes which fragment and where merge runs.

## 3. Database

| Field | Options |
|--------|---------|
| Single test DB | Omitting `databases:` in `polyrun.yml` may be enough; ensure parallel workers do not share one DB if they mutate data |
| Multi-DB or shard suffixes | `databases:` in `polyrun.yml` (`shard_db_pattern`, `template_db`, optional `connections` and `env_key`). `database.yml` or `DATABASE_URL` may use `%{shard}` or `POLYRUN_SHARD_INDEX` suffixes—the same convention as `polyrun env` |
| External provisioning | Sometimes `db:prepare` plus shell clone scripts (multi-DB apps)—document ordering: prepare databases before `run-shards` |

## 4. Prepare (run once before workers)

| Field | Options |
|--------|---------|
| None | Typical for gems without assets |
| Assets | `Polyrun::Prepare::Assets`, `prepare.recipe: assets` or `default`, digest markers |
| Playwright / browsers | Install once in prepare; workers skip reinstall (`SKIP_*` env flags in app code if needed) |
| Custom shell | `prepare.recipe: shell` with `prepare.command:`—must not repeat heavy work inside each worker |

Rule: anything expensive (compile, `yarn`, Playwright download) belongs in prepare or a CI cache step, not in `before(:suite)` per worker unless gated by `POLYRUN_SHARD_TOTAL` or similar env.

## 5. Spec list and ordering

| Field | Options |
|--------|---------|
| Plain glob | `partition.paths_build.all_glob: spec/**/*_spec.rb` and empty or minimal `stages` |
| Ordered stages | `partition.paths_build.stages`: regex (e.g. slow integration first) or `sort_by_substring_order` for stable ordering |
| Exclude prefixes | `partition.paths_build.exclude_prefixes`: omit paths (e.g. `spec/benchmark/`) from `paths_file` while keeping them runnable outside polyrun |

`paths_build` controls **membership** in `partition.paths_file`, not shard assignment order. Default `round_robin` sorts paths alphabetically before mod assignment. Use `strategy: preserve_order_round_robin` to honor paths-file line order. Set `partition.timing_file` without `strategy` to auto-select `cost_binpack`; use `lazy_robin` for round-robin assignment with timing diagnostics.

Refresh list: `polyrun -c polyrun.yml build-paths` (also runs automatically before `plan` / `run-shards` when configured).

## 5b. Parallel worker logs (opt-in)

When `run-shards` fans out multiple workers, stdout/stderr interleave on the parent TTY by default.

| Env | Effect |
|--------|--------|
| `POLYRUN_WORKER_OUTPUT_ROUTING=1` | Route each worker through per-shard log files (default dir `tmp/polyrun/workers`) |
| `POLYRUN_WORKER_LOG_DIR` | Custom log directory (also enables routing when set) |
| `POLYRUN_WORKER_OUTPUT_ROUTING=0` | Force inherited stdio even when log dir is set |
| `POLYRUN_WORKER_OUTPUT_PREFIX=0` | Write logs only; no live prefixed TTY echo |

Carriage-return progress chunks (Fuubar-style) pass through unprefixed on the TTY and in logs.

## 5c. RSpec example debug (local investigation)

Orchestration tracing stays on `DEBUG=1` / `POLYRUN_DEBUG=1`. Per-example tooling is separate:

| Env | Effect |
|--------|--------|
| `POLYRUN_EXAMPLE_DEBUG=1` | Enable example debug installers |
| `POLYRUN_DEBUG_SQL=1` or `DEBUG_SQL=1` | Log mutating SQL |
| `POLYRUN_DEBUG_TRACE=1` or `DEBUG_TRACE=1` | TracePoint under app root |
| `DEBUG_PROSOPITE=1` | Prosopite N+1 scan when gem is loaded |
| `RSPEC_EXAMPLE_TIMEOUT_SEC` | Per-example timeout (disabled while example debug is on) |

In `spec_helper` / `spec/support`: `require "polyrun/rspec"` then `Polyrun::RSpec.install_example_debug!`, `install_example_rails_logging!`, `install_example_timeout!`, and `install_sharded_formatter_compat!` when using Fuubar under `POLYRUN_SHARD_*`. Pair with `install_worker_ping!` for idle timeouts.

## 6. Coverage and CI reports

| Field | Options |
|--------|---------|
| Collector | `require "polyrun"` plus `Polyrun::Coverage::Collector.start!` in `spec_helper` (non-Rails gems) |
| Rails | `require "polyrun/coverage/rails"` (or documented Rails integration) in `spec_helper` / `test_helper` |
| Fragments | Per shard: `coverage/polyrun-fragment-<shard>.json` |
| Merge | `polyrun merge-coverage` on fragments → merged JSON; then `polyrun report-coverage` (formats: json, lcov, cobertura, console, html, …) |
| JUnit | `polyrun report-junit` from RSpec JSON if needed |

## 7. `polyrun.yml` as contract — adapters

After `polyrun.yml` is fixed, add or adjust adapters (same shard semantics):

| Adapter | Role |
|---------|------|
| `bin/rspec_parallel` / `bin/rspec_ci_shard` | Thin wrappers: prepare, start, or plan + rspec |
| `bin/polyrun-rspec` | Single shard (`env` + plan + rspec), e.g. one matrix cell or ad-hoc run |
| `config/database.yml` | ERB / suffixes matching `databases.shard_db_pattern` |
| Prepare script | Referenced from `prepare.command` |
| `POLYRUN.md` (or `spec/README`) | Canonical commands for this repo; CI model (below) |

Bot workflow: read and write `polyrun.yml` first, then generate or patch wrappers and docs to match.

## 8. CI models (document one in `POLYRUN.md`)

Model A — one job, N worker processes

- Command: `polyrun -c polyrun.yml parallel-rspec --workers N` (or `polyrun start`). Global `-c` / `-v` / `-h` must appear before the subcommand.
- Coverage fragments appear on the same runner; `merge-coverage` can run in the same job after workers finish.

Model B — matrix of jobs (one shard per job)

- Each job sets `POLYRUN_SHARD_INDEX` / `POLYRUN_SHARD_TOTAL` (and DB URLs per shard if needed).
- Run `polyrun ci-shard-run -- bundle exec rspec` (or `ci-shard-rspec`), or `ci-shard-run -- bundle exec polyrun quick` / other runners; or the same steps manually (`bin/rspec_ci_shard` wrappers).
- Upload `coverage/polyrun-fragment-*.json` (or named per shard).
- A final `merge-coverage` job downloads artifacts and merges.

GitHub Actions does not set `CI_NODE_INDEX` / `CI_NODE_TOTAL` by default—set `POLYRUN_*` explicitly in the matrix.

## 9. Chatbot / agent context blocks (high signal)

1. Upstream README sections: partition, prepare, databases, merge-coverage, `Env::Ci` (shard detection).
2. Project `polyrun.yml` (filled in) plus one of: `POLYRUN.md` or `spec/README.md` with the canonical test command and CI model (A or B).
3. Exact `Gemfile` / Appraisal lines for `polyrun` and any Docker or path notes.

## 10. Scaffold from this repo

```bash
polyrun init --list
polyrun init --profile gem -o polyrun.yml
polyrun init --profile rails -o polyrun.yml
polyrun init --profile ci-matrix -o polyrun.yml
polyrun init --profile doc -o POLYRUN.md    # host-project doc template
```

Templates live under `lib/polyrun/templates/` in the gem. See `examples/templates/README.md` for profile descriptions.
