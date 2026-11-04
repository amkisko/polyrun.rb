# Host config contract gaps

## Decisions

Promote three repeated host-glue signals into core contracts: coverage config resolution (file vs inline), top-level YAML `workers:`, and Rails init template alignment with the live Rails archetype. Defer named suites, doctor, prepare rake generator, and CI fragments to later issues.

## Effects

The iterative diff audit reproduced and fixed seven config, coverage, validation, and diagnostic defects. Evidence and validation commands: `docs/reviews/20261104181000_diff-engineering-audit.md`.

Fact-check of `docs/plan/20261104145000_host-config-patterns-core-dx.md` against this tree:

- Config already auto-resolves `polyrun.yml` / `config/polyrun.yml` and `POLYRUN_CONFIG`; worker clamp 1..10 already lives in core. Plan item 1 is mostly documentation and optional one-liner binstub, not a missing load path.
- Named `suites:` / `--suite` for partition membership overrides is absent. Existing `partition.suite` only selects rspec / minitest / quick runners.
- Rails init template lacks `start:`, hooks stubs, and `reporting.merge_failures` commentary; multi-DB `connections` already appear in comments. No engine-with-dummy profile.
- `Coverage::Rails` loads only `config/polyrun_coverage.yml`. Inline `coverage:` on `polyrun.yml` is readable via `Config#coverage` but unused. Gate helper likewise ignores inline coverage. Host key aliases `formats` / `output_path` are not normalized to `report_formats` / `report_output_dir`.
- Top-level YAML `workers:` is overwritten by `Config::Effective` and never consulted by `run-shards` / `start` defaults (ENV or hard default only).
- No `polyrun validate` / `doctor`. `polyrun config` requires a dotted path.
- Skip env names: start uses `POLYRUN_START_SKIP_*`; paths build uses `POLYRUN_SKIP_*`. Confirmed dual vocabulary; collapse deferred.

Audit modes run: contracts, resource and budget (config resolve / Effective.build hot path), trace and identification (skip: no new person identifiers), product-surface (CLI templates and validate messages), security (skip new trust boundary; YAML already trusted from cwd). Boundary and control skipped (library, no plant). Privacy / learned-systems / lineage skipped (no matching surface).

## Next

- Engine-with-dummy init profile; optional `polyrun.<name>.yml` auto-discovery; nested `polyrun help debug`.

Done: coverage resolve, YAML workers, rails init shape, `polyrun validate`, named `suites:` / `--suite`, `polyrun doctor`, `rails-prepare-task` init profile, skip-env collapse (`POLYRUN_SKIP_*` canonical). Benchmarks under `tmp/benchmarks/`.

## Source

- `docs/plan/20261104145000_host-config-patterns-core-dx.md`
- `lib/polyrun/config.rb`, `lib/polyrun/config/effective.rb`, `lib/polyrun/config/resolver.rb`
- `lib/polyrun/coverage/rails.rb`, `lib/polyrun/cli/helpers.rb`, `lib/polyrun/templates/rails_prepare.polyrun.yml`
