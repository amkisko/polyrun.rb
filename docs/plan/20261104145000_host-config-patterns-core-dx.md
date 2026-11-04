# Host config patterns and core developer experience

Design notes from repeated Polyrun host glue patterns. Anonymous: no host names, paths, credentials, product titles, or org identifiers.

## Decisions

Treat repeated host glue as a product signal. When many repos copy the same wrapper, rake task, or second YAML file, the core gem should absorb a default or a first-class profile.

Keep host-only policy in the host: coverage floors, reject lists tied to app layout, chat after-suite hooks, and one-off partition constraints. Promote mechanics that every Rails or gem host reinvents the same way.

## Effects

### Shape of configs in the notes

Hosts commonly expose a root `polyrun.yml`. Apps often also keep `config/polyrun_coverage.yml`; some keep `config/polyrun_spec_quality.yml`. Some hosts keep near-duplicate named suite files beside the root config (for example `polyrun.unit.yml` / `polyrun.system.yml`).

Two stable archetypes recur:

1. Library / gem minimal: `version`, inline `coverage` (formats + output path), and `partition.paths_build.all_glob` only. Often no `databases`, `prepare`, `hooks`, or `start`.
2. Rails / engine full: `partition` with `paths_file`, `shard_total`, `strategy`, `paths_build`; `prepare` with `recipe: shell` and a Rails prepare task; `start` toggles for prepare and databases; `databases` with template + shard pattern (PostgreSQL common, MySQL present); optional multi-DB `connections` with `env_key`; `hooks` before/after suite; `reporting.merge_failures`.

Mixed middle cases exist (gems with a dummy Rails app, prepare without databases, databases without hooks). Init templates today cover gem and Rails prepare. Live hosts often keep a richer Rails file: a start block, hooks, merge_failures, and multi-DB connections.

### Shared configuration patterns

- `partition.paths_build.all_glob` is common in these notes; `exclude_prefixes` and `stages` appear when hosts split slow or serial paths.
- Default strategy is `round_robin`. Advanced strategies (`weighted_hrw`, serial constraints, custom shard weights) appear mainly when a full suite cannot split CI jobs and needs serial browser or system work on one shard.
- `prepare.recipe: shell` plus one Rails prepare invocation is the common prepare shape. Hosts still own a rake task that implements assets, Playwright, digests, and skip flags.
- `start.databases` and `start.prepare` are the usual bootstrap gates; CI often skips prepare via env and runs it in an earlier job step.
- Coverage gate config lives separately from orchestration YAML more often in apps; gems often inline a short `coverage:` block in `polyrun.yml`. Track roots cluster on `lib` / `app` / `config`. Reject patterns and `minimum_line_percent` vary widely by host policy.
- Spec setup in these notes uses the Rails coverage entry and env-gated coverage. Spec quality install is common; SimpleCov beside Polyrun is rare.
- CI language clusters on `parallel-rspec`, then `report-coverage` / `report-junit`, sometimes `merge-coverage`. Matrix `ci-shard-*` is rare relative to single-job multi-worker runs.
- Workflow env in these notes covers workers, shard index and total, skip prepare, worker logs, failure fragments, and idle timeout or ping.

### What is custom (and should stay host-owned)

- Coverage floors, track/reject lists, and report groups that mirror application layout.
- After-suite notifications and failure fragment cleanup scripts.
- Playwright / Node / asset toolchain versions and digest skip rules inside prepare rake tasks.
- App-specific serial globs, shard weights, and suite splits (unit vs system vs e2e).
- Appraisal multi-gemfile orchestration details beyond a thin binstub.
- Chat or other side-channel reporting.

### What is custom today but looks like missing core product

- `bin/polyrun` shell wrappers: many near-copies of the same shim (cwd, worker clamp 1..10, default config path, pass-through to `start` / parallel). The copied shim is a default CLI gap.
- `lib/tasks/polyrun_prepare.rake`: many near-copies of assets + Playwright prepare with skip markers. Core already has prepare recipes; hosts still reimplement the Rails task surface.
- Named suite YAML files duplicated from a root config with only `paths_build` / `shard_total` changed. No first-class `suites:` or `--suite` selection in the contract hosts use.
- Dual coverage config locations (inline `coverage:` and `config/polyrun_coverage.yml`). The contract needs one resolution order hosts can copy once.
- `database.yml` ERB shard awareness copied per app even when `databases:` already describes the same pattern.
- Top-level `workers:` in some configs vs `POLYRUN_WORKERS` / CLI flags elsewhere.
- Inconsistent `version:` presence. Schema checks remain a social convention.

## Next

Ranked suggestions for the Polyrun core gem. Prefer small contracts that delete host glue.

### 1. First-class local entry (replace copied `bin/polyrun`)

Ship a stable default local command path. A one-line binstub replaces the copied shell shim:

- Resolve config from cwd or `POLYRUN_CONFIG` when `polyrun.yml` exists, including calls that omit `-c`.
- Clamp workers the same way wrappers do (document defaults; keep env override).
- Make bare `polyrun` / `polyrun start` the documented local path; treat `bin/polyrun` as optional one-liner `exec bundle exec polyrun "$@"`.
- Optional `polyrun init --profile binstub` that writes that one-liner.

### 2. Named suites in one config

Add a `suites:` (or `profiles:`) map under one `polyrun.yml`:

- Each suite overrides partition membership (`all_glob`, excludes, stages, shard_total, strategy, constraints) and optionally workers.
- CLI: `polyrun --suite unit start`, `polyrun --suite system parallel-rspec`.
- CI selects a suite from that file and drops the near-duplicate YAML files.
- Keep file-based `-c polyrun.unit.yml` working for compatibility.

### 3. Align init templates with the live Rails archetype

Extend the Rails init profile to match what hosts actually keep:

- `start.prepare` / `start.databases`
- `reporting.merge_failures: true` (opt-in comment today; default comment that matches practice)
- `hooks.before_suite` / `after_suite` stubs
- `databases.connections` example for multi-DB
- Document the MySQL path as URL shaping. Clone stays a prepare-script concern.

Add a third profile for "engine gem with dummy Rails" between minimal gem and full app.

### 4. Coverage config contract

One resolution order, printed by `polyrun config` / `polyrun doctor`:

1. `POLYRUN_COVERAGE_*` env
2. `config/polyrun_coverage.yml` when present
3. inline `coverage:` in the active polyrun config

Init profile for coverage with common `track_under: [lib, app]` and an empty reject list. Use one pair of basename and output-directory keys.

### 5. Prepare: Rails task generator

The notes point to `rails polyrun:prepare` with pluggable steps (assets, Playwright, custom). Offer:

- `polyrun init --profile rails-prepare-task` writing a small rake file that calls Polyrun prepare helpers
- One skip spelling owned by the gem: `POLYRUN_SKIP_PREPARE` and `POLYRUN_SKIP_DATABASES`, with `POLYRUN_START_SKIP_*` kept as a deprecated alias through a deprecation window.

### 6. Doctor and effective config

`polyrun doctor` (or expand `polyrun config` / `env`):

- Which config file and suite are active
- Whether prepare and databases will run on `start`
- Shard DB names that will be created (Postgres) vs URLs only (MySQL)
- Coverage gate file in use and whether `POLYRUN_COVERAGE_DISABLE` is set
- Warning when both matrix shard env and in-process workers are set
- Warning when named suite files diverge from root on shared keys (databases/hooks)

This prints the effective settings that host YAML comments currently explain.

### 7. Reduce env vocabulary pressure

Publish a short layered cheat sheet and mirror it in `polyrun help` sections:

- Always: `POLYRUN_CONFIG`, `POLYRUN_WORKERS`, `POLYRUN_COVERAGE`, `POLYRUN_COVERAGE_DISABLE`
- Start/CI: `POLYRUN_START_SKIP_PREPARE`, `POLYRUN_START_SKIP_DATABASES`, shard index/total
- Debug: worker output routing, example debug, merge profiling

Hide or nest advanced vars behind `polyrun help debug` so the default help stays scannable. In these notes, hosts paste large env blocks into workflows.

### 8. CI workflow fragments

Init profiles or docs snippets for the two models already in SETUP_PROFILE:

- Model A: one job, `parallel-rspec --workers N`, merge and report in the same job
- Model B: matrix `ci-shard-rspec` + merge job (rare but supported)

Generate GitHub Actions fragments with placeholders only (no org/product names). The notes show Model A more often than Model B, so templates should bias that way.

### 9. Schema validation

Optional `version: 1` enforcement with `polyrun validate`:

- Unknown top-level keys warn
- Required keys per archetype (gem vs rails) from init profiles
- Mutual exclusion: serial constraints require a strategy that honors them

Fails CI early when a host typos `path_build` or puts `workers` in the wrong place.

### 10. Partition power tools stay, but document when

Keep weighted / serial / timing strategies. Add one anonymous worked example for "system specs serial on shard 0, unit specs on others," with one constraint shape. Recommend a suite split (`unit` / `system`) first. Reserve weighted_hrw for a single-run full suite that stays in one CI job.

## Source

- Anonymous pattern notes from repeated Polyrun host glue (YAML shape, wrappers, prepare tasks, CI command clusters); no host inventory.
- Polyrun 2.2.7 CLI help, init profiles (`gem`, `rails`, `ci-matrix`, `spec-quality`, `doc`), and SETUP_PROFILE checklist.
- Design-only; no host repo edits in the planning pass.

## Open questions

- Should named suites live only in YAML, or also as convention `polyrun.<name>.yml` auto-discovery?
- Should the gem vendor a minimal `bin/polyrun` via `polyrun init`, or teach Bundler binstubs enough that hosts need nothing?
- Is MySQL shard provisioning in scope for core, or permanently a prepare-script concern?
- How far should coverage policy move into the gem versus staying a host gate file?

## Fact-check (core tree, 2026-11-04)

- Item 1 overstated the load gap. cwd, `POLYRUN_CONFIG`, and the default filenames already resolve, and the worker clamp 1..10 already lives in core. Remaining work is an optional one-line binstub profile and a docs bias toward that path.
- Item 2 is in core: `suites:` plus `--suite` or `POLYRUN_SUITE`. File-based `-c` still works. Runner `partition.suite` is unchanged.
- Item 3 is in core for `start`, hooks, `merge_failures` commentary, and `version`. Multi-DB connections were already commented in the template.
- Item 4 was a real gap and is fixed: dedicated file, then inline coverage, plus format aliases.
- Item 5 is in core: the `rails-prepare-task` init profile. `POLYRUN_SKIP_PREPARE` and `POLYRUN_SKIP_DATABASES` are canonical, and the legacy names remain aliases.
- Item 6 is in core: `polyrun doctor`. `polyrun config` still requires a dotted path.
- Item 7 is partial. Help text now covers workers, coverage resolve, suite, and skip env. The layered cheat sheet is still open.
- Item 8 is still open: CI fragments.
- Item 9 is partial. `polyrun validate` rejects unknown top-level keys. Archetype required-key sets are still open.
- Item 10 is still open: a worked partition example.

Live-work record: `docs/issues/20261104153500_host-config-contract-gaps.md`.
