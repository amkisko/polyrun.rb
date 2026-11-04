# Host config patterns and core DX improvements

Design notes from repeated Polyrun host glue patterns. Anonymous: no host names, paths, credentials, product titles, or org identifiers.

## Decisions

Treat repeated host glue as a product signal: when many repos copy the same wrapper, rake task, or second YAML file, the core gem should absorb a default or a first-class profile rather than leave each host to reinvent it.

Keep host-only policy in the host: coverage floors, reject lists tied to app layout, chat after-suite hooks, and one-off partition constraints. Promote mechanics that every Rails or gem host reinvents the same way.

## Effects

### Shape of configs seen in the wild

Hosts commonly expose a root `polyrun.yml`. Apps often also keep `config/polyrun_coverage.yml`; some keep `config/polyrun_spec_quality.yml`. A minority keep near-duplicate named suite files beside the root config (for example `polyrun.unit.yml` / `polyrun.system.yml`).

Two stable archetypes dominate:

1. Library / gem minimal: `version`, inline `coverage` (formats + output path), and `partition.paths_build.all_glob` only. Often no `databases`, `prepare`, `hooks`, or `start`.
2. Rails / engine full: `partition` with `paths_file`, `shard_total`, `strategy`, `paths_build`; `prepare` with `recipe: shell` and a Rails prepare task; `start` toggles for prepare and databases; `databases` with template + shard pattern (PostgreSQL common, MySQL present); optional multi-DB `connections` with `env_key`; `hooks` before/after suite; `reporting.merge_failures`.

Mixed middle cases exist (gems with a dummy Rails app, prepare without databases, databases without hooks). Init templates today cover gem and Rails prepare, but live hosts often look richer than the Rails template (start block, hooks, merge_failures, multi-DB connections).

### Shared configuration patterns

- `partition.paths_build.all_glob` is nearly universal; `exclude_prefixes` and `stages` appear when hosts split slow or serial paths.
- Default strategy is `round_robin`. Advanced strategies (`weighted_hrw`, serial constraints, custom shard weights) appear mainly when a full suite cannot split CI jobs and needs serial browser or system work on one shard.
- `prepare.recipe: shell` plus one Rails prepare invocation is the common prepare shape. Hosts still own a rake task that implements assets, Playwright, digests, and skip flags.
- `start.databases` and `start.prepare` are the usual bootstrap gates; CI often skips prepare via env and runs it in an earlier job step.
- Coverage gate config lives separately from orchestration YAML more often in apps; gems often inline a short `coverage:` block in `polyrun.yml`. Track roots cluster on `lib` / `app` / `config`. Reject patterns and `minimum_line_percent` vary widely by host policy.
- Spec setup almost always uses the Rails coverage entry and env-gated coverage. Spec quality install is common; SimpleCov-beside-Polyrun is rare.
- CI language clusters on `parallel-rspec`, then `report-coverage` / `report-junit`, sometimes `merge-coverage`. Matrix `ci-shard-*` is rare relative to single-job multi-worker runs.
- Env surface in workflows is large: workers, shard index/total, skip prepare, worker logs, failure fragments, idle timeout / ping. Hosts must learn many switches.

### What is custom (and should stay host-owned)

- Coverage floors, track/reject lists, and report groups that mirror application layout.
- After-suite notifications and failure fragment cleanup scripts.
- Playwright / Node / asset toolchain versions and digest skip rules inside prepare rake tasks.
- App-specific serial globs, shard weights, and suite splits (unit vs system vs e2e).
- Appraisal multi-gemfile orchestration details beyond a thin binstub.
- Chat or other side-channel reporting.

### What is custom today but looks like missing core product

- `bin/polyrun` shell wrappers: many near-copies of the same shim (cwd, worker clamp 1..10, default config path, pass-through to `start` / parallel). This is a default CLI UX gap, not host policy.
- `lib/tasks/polyrun_prepare.rake`: many near-copies of assets + Playwright prepare with skip markers. Core already has prepare recipes; hosts still reimplement the Rails task surface.
- Named suite YAML files duplicated from a root config with only `paths_build` / `shard_total` changed. No first-class `suites:` or `--suite` selection in the contract hosts use.
- Dual coverage config locations (inline `coverage:` vs `config/polyrun_coverage.yml`) without a single documented resolution story that hosts can copy once.
- `database.yml` ERB shard awareness copied per app even when `databases:` already describes the same pattern.
- Top-level `workers:` in some configs vs `POLYRUN_WORKERS` / CLI flags elsewhere.
- Inconsistent `version:` presence; schema validation is effectively social, not enforced.

## Next

Ranked suggestions for the Polyrun core gem. Prefer small contracts that delete host glue.

### 1. First-class local entry (replace copied `bin/polyrun`)

Ship a stable default local command path so hosts do not need a 100-line shell shim:

- Resolve config from cwd / `POLYRUN_CONFIG` without forcing `-c` on every call when `polyrun.yml` exists.
- Clamp workers the same way wrappers do (document defaults; keep env override).
- Make bare `polyrun` / `polyrun start` the documented local path; treat `bin/polyrun` as optional one-liner `exec bundle exec polyrun "$@"`.
- Optional `polyrun init --profile binstub` that writes the one-liner, not a second orchestration layer.

### 2. Named suites in one config

Add a `suites:` (or `profiles:`) map under one `polyrun.yml`:

- Each suite overrides partition membership (`all_glob`, excludes, stages, shard_total, strategy, constraints) and optionally workers.
- CLI: `polyrun --suite unit start`, `polyrun --suite system parallel-rspec`.
- CI selects a suite without maintaining near-duplicate YAML files.
- Keep file-based `-c polyrun.unit.yml` working for compatibility.

### 3. Align init templates with the live Rails archetype

Extend the Rails init profile to match what hosts actually keep:

- `start.prepare` / `start.databases`
- `reporting.merge_failures: true` (opt-in comment today; default comment that matches practice)
- `hooks.before_suite` / `after_suite` stubs
- `databases.connections` example for multi-DB
- Document MySQL path: URL shaping yes, auto clone no

Add a third profile for "engine gem with dummy Rails" between minimal gem and full app.

### 4. Coverage config contract

One resolution order, printed by `polyrun config` / `polyrun doctor`:

1. `POLYRUN_COVERAGE_*` env
2. `config/polyrun_coverage.yml` when present
3. inline `coverage:` in the active polyrun config

Init profile for coverage with common `track_under: [lib, app]` and empty reject list. Avoid requiring hosts to invent basename / output dir keys twice.

### 5. Prepare: ship a Rails task generator, not only shell recipe

Most hosts want `rails polyrun:prepare` with pluggable steps (assets, Playwright, custom). Offer:

- `polyrun init --profile rails-prepare-task` writing a small rake file that calls Polyrun prepare helpers
- Clear skip env names owned by the gem (`POLYRUN_SKIP_*`) so hosts stop inventing parallel spellings (`POLYRUN_SKIP_PREPARE` vs `POLYRUN_START_SKIP_PREPARE`)

Collapse duplicate skip env names over a deprecation window.

### 6. Doctor / effective-config DX

`polyrun doctor` (or expand `polyrun config` / `env`):

- Which config file and suite are active
- Whether prepare and databases will run on `start`
- Shard DB names that will be created (Postgres) vs URLs only (MySQL)
- Coverage gate file in use and whether `POLYRUN_COVERAGE_DISABLE` is set
- Warning when both matrix shard env and in-process workers are set
- Warning when named suite files diverge from root on shared keys (databases/hooks)

This replaces tribal knowledge currently encoded in long comments inside host YAML.

### 7. Reduce env vocabulary pressure

Publish a short layered cheat sheet and mirror it in `polyrun help` sections:

- Always: `POLYRUN_CONFIG`, `POLYRUN_WORKERS`, `POLYRUN_COVERAGE`, `POLYRUN_COVERAGE_DISABLE`
- Start/CI: `POLYRUN_START_SKIP_PREPARE`, `POLYRUN_START_SKIP_DATABASES`, shard index/total
- Debug: worker output routing, example debug, merge profiling

Hide or nest advanced vars behind `polyrun help debug` so the default help stays scannable. Hosts currently paste large env blocks because discovery is hard.

### 8. CI workflow fragments

Init profiles or docs snippets for the two models already in SETUP_PROFILE:

- Model A: one job, `parallel-rspec --workers N`, merge + report in-job (matches most hosts)
- Model B: matrix `ci-shard-rspec` + merge job (rare but supported)

Generate GitHub Actions fragments with placeholders only (no org/product names). Most CI copy today is Model A; templates should bias that way.

### 9. Schema validation

Optional `version: 1` enforcement with `polyrun validate`:

- Unknown top-level keys warn
- Required keys per archetype (gem vs rails) from init profiles
- Mutual exclusion: serial constraints require a strategy that honors them

Fails CI early instead of silent ignore when a host typos `path_build` or puts `workers` in the wrong place.

### 10. Partition power tools stay, but document when

Keep weighted / serial / timing strategies. Add one worked example in docs (anonymous) for "system specs serial on shard 0, unit specs on others" so hosts do not invent incompatible constraint shapes. Prefer suite split (`unit` / `system`) as the default recommendation; reserve weighted_hrw for single-run full suites that cannot split CI jobs.

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

- Item 1 partly false as a load gap: cwd / `POLYRUN_CONFIG` / default filenames already resolve; worker clamp 1..10 already in core. Remaining: optional one-liner binstub profile and docs bias.
- Item 2 addressed: `suites:` + `--suite` / `POLYRUN_SUITE` (file-based `-c` still works). Runner `partition.suite` unchanged.
- Item 3 partial: rails template lacked `start` / hooks / merge_failures commentary; multi-DB connections already commented. Addressed in core for start/hooks/merge_failures/`version`.
- Item 4 true gap then fixed: file vs inline coverage resolve + format aliases.
- Item 5 addressed: `rails-prepare-task` init profile; `POLYRUN_SKIP_PREPARE` / `POLYRUN_SKIP_DATABASES` canonical with legacy aliases.
- Item 6 addressed: `polyrun doctor`; `config` dotted-path remains.
- Item 7 partial: help text updated for workers, coverage resolve, suite, skip env; layered cheat sheet deferred.
- Item 8 deferred (CI fragments).
- Item 9 partial: `polyrun validate` unknown top-level keys shipped; archetype required-key sets deferred.
- Item 10 deferred (worked partition example docs).

Live-work record: `docs/issues/20261104153500_host-config-contract-gaps.md`.
