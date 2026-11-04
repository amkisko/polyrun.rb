# Host config contract gaps

## Decisions

Promote repeated host-glue into core contracts: coverage resolution (dedicated file, then inline), top-level YAML `workers:`, Rails init alignment, named `suites:`, `polyrun validate`, `polyrun doctor`, the `rails-prepare-task` init profile, and canonical `POLYRUN_SKIP_*` names.

The opening pass named only coverage resolve, YAML workers, and Rails init alignment, and left the rest for later issues. Before the 2.2.8 cut this issue also took named suites, doctor, the prepare-task profile, and skip-env collapse.

## Effects

The diff audit reproduced and fixed seven config, coverage, validation, and diagnostic defects. Evidence and commands: `docs/reviews/20261104181000_diff-engineering-audit.md`.

Opening fact-check of `docs/plan/20261104145000_host-config-patterns-core-dx.md`, then the 2.2.8 result:

- Config already resolved `polyrun.yml` / `config/polyrun.yml` and `POLYRUN_CONFIG`. The worker clamp 1..10 already lived in core. Plan item 1 remains documentation and an optional one-line binstub.
- `suites:` with `--suite` / `POLYRUN_SUITE` deep-merges partition membership and related keys. `partition.suite` still selects the rspec, minitest, or quick runner.
- The Rails init template includes `version`, `start`, empty `hooks`, and `merge_failures` commentary. Multi-DB `connections` were already in comments.
- Coverage resolution uses `config/polyrun_coverage.yml` when that file is present, and otherwise inline `coverage:`. Aliases `formats` and `output_path` map to `report_formats` and `report_output_dir`. The line gate uses the same resolution.
- Top-level YAML `workers:` feeds `start`, `run-shards`, `run-queue`, and `polyrun config workers` when `POLYRUN_WORKERS` is unset.
- `polyrun validate` rejects unknown top-level keys and a non-mapping root. `polyrun doctor` prints the effective summary. `polyrun config` still requires a dotted path.
- Canonical skip names are `POLYRUN_SKIP_PREPARE` and `POLYRUN_SKIP_DATABASES`. Legacy `POLYRUN_START_SKIP_*` still runs and warns.

Audit modes run: contracts, resource and budget (config resolve and Effective.build), trace and identification (no new person identifiers), product-surface (CLI templates and validate messages), security (YAML stays trusted from the working directory; no new trust boundary). Boundary and control covers CLI commands and child-process feedback; this library has no physical plant. Privacy, learned-systems, and lineage had no matching surface.

## Next

- Engine-with-dummy init profile.
- Optional `polyrun.<name>.yml` auto-discovery.
- Nested `polyrun help debug`.
- CI workflow fragments, archetype required-key sets, and a worked partition example.

Release note: `docs/changelogs/20261104181846_release-2-2-8.md`. Benchmarks under `tmp/benchmarks/`.

## Source

- `docs/plan/20261104145000_host-config-patterns-core-dx.md`
- `lib/polyrun/config.rb`, `lib/polyrun/config/effective.rb`, `lib/polyrun/config/resolver.rb`
- `lib/polyrun/coverage/rails.rb`, `lib/polyrun/cli/helpers.rb`, `lib/polyrun/templates/rails_prepare.polyrun.yml`
