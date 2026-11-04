# Host config contract fixes

## Decisions

Ship host-glue DX contracts in two passes: first coverage resolve, YAML workers, Rails init alignment, and validate; then named suites, doctor, prepare-task init profile, and skip-env collapse.

## Effects

- Honor the selected suite and explicit config throughout coverage collection and merging; restore invocation settings and correct validate/doctor diagnostics. Replication and fix evidence: `docs/reviews/20261104181000_diff-engineering-audit.md`.

- `Polyrun::Coverage::ConfigResolve` feeds `Coverage::Rails` and the merge coverage line gate.
- `Config::Resolver.parallel_worker_count` used by Effective, run-shards, start, and run-queue.
- `polyrun validate` exits 1 on unknown top-level keys (e.g. typo `path_build`).
- Rails init template includes `version`, `start.prepare` / `start.databases`, `hooks: {}`, and `merge_failures` commentary.
- `suites:` map + `--suite` / `POLYRUN_SUITE` deep-merges partition (and optional workers / prepare / start / hooks / reporting / coverage / databases) via `Config::Suite`.
- `polyrun doctor` prints config path, active suite, workers, start gates, DB adapter and shard names (Postgres) or URL-shaping-only (other adapters), coverage source, and matrix+workers warning.
- Canonical skip env: `POLYRUN_SKIP_PREPARE` / `POLYRUN_SKIP_DATABASES`; legacy `POLYRUN_START_SKIP_*` still works with a deprecation warning.
- `polyrun init --profile rails-prepare-task` writes `lib/tasks/polyrun_prepare.rake`.
- Benchmark (reps=2000, Ruby 4.0.2): Effective.build ~0.014ms/op; ConfigResolve file ~0.11ms/op; inline ~0.076ms/op; Suite.merge ~0.006ms/op.
- Cut into 2.2.8.

## Next

- Optional engine-with-dummy init profile.
- Optional `polyrun.<name>.yml` auto-discovery alongside `suites:`.
- Broader env help nesting (`polyrun help debug`).

## Source

- `docs/issues/20261104153500_host-config-contract-gaps.md`
- `docs/plan/20261104145000_host-config-patterns-core-dx.md`
