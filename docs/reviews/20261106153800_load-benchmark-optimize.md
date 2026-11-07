# Load benchmark and coverage-merge pressure harness

## Participants

Andrei Makarov (@amkisko)

## Decisions

- Add `Polyrun::Benchmark::Pressure` as the shared Ruby sampler (wall, CPU, RSS, heap, GC, optional storage/network byte deltas) and target ceilings (`DEFAULT_TARGET_FACTOR` 0.85) for iterative pressure runs across sibling gems.
- Add maintainer load harness `benchmarks/load.rb` + `make bench-load` for coverage-merge matrix (`disk` baseline → hotter disk → `tree` → `merge_two`).
- Keep existing `benchmark/merge_coverage.rb` and RSpec `:benchmark` specs; Pressure is the resource-focused path.
- Do not change merge algorithms in this round; first matrix run is the published baseline for the next cut.

## Effects

### Harness

- `lib/polyrun/benchmark/pressure.rb`
- `benchmarks/load.rb`
- `spec/polyrun/benchmark/pressure_spec.rb`
- `make bench-load`
- Env: `SCENARIO=matrix|disk|tree|two|heavy`, `MERGE_FILES`, `MERGE_LINES`, `MERGE_FRAGMENTS`, `MERGE_REPS`, `TARGET_FACTOR`
- JSON under `benchmarks/output/` (gitignored)

### Observed baseline (matrix, 60 files × 120 lines × 6 fragments, 1 rep)

Host-relative; sample `benchmarks/output/20261106153808_load.json` (Ruby 4.0.2). RSS may read 0 under restricted sandboxes (`ps` denied).

| Scenario | wall (s) | ops/s | alloc | storage_Δ | notes |
| --- | ---: | ---: | ---: | ---: | --- |
| baseline_disk | ~0.010 | ~587 | ~4.8k | ~107 KiB | 6 fragments |
| pressure_disk 90×120×10 | ~0.024 | ~426 | ~12.4k | ~267 KiB | FAIL vs 0.85× scaled targets (storage/ops rose faster than linear) |
| tree | ~0.007 | ~808 | ~3.2k | — | in-memory blob tree |
| merge_two | ~0.002 | ~435 | ~820 | — | pair merge |

### Code changes landed with this review

- `Polyrun::Benchmark::Pressure` sample / measure / targets / JSON writer
- `benchmarks/load.rb` pressure matrix
- CHANGELOG Unreleased bullets
- Spec for measure + target math

## Next

- Cut into 2.2.9; siblings can depend on the released gem instead of `../../polyrun.rb/lib`.
- Profile hotter-than-L1 sizes after publish if storage_Δ or wall drifts above ceilings.
- Re-check RSS with an unrestricted local shell before citing memory numbers externally.

## Source

- `lib/polyrun/benchmark/pressure.rb`
- `benchmarks/load.rb`
- Sample JSON: `benchmarks/output/*_load.json` (local only)
