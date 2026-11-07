# Pressure cooker episode — polyrun coverage merge (**accepted**)

## Meta

- **Repository revision**: `733d16494ad45ee9a535e2fbd74adbab422c69a4`
- **Machine class**: `arm64` (Darwin)
- **Network**: `not_in_scope` (local fixtures only)
- **Memory probe class**: `process_lifetime` (per `benchmarks/binding.md`)

## Calibrate

- **Command**: `env -u BUNDLE_PATH SCENARIO=calibrate bundle exec ruby benchmarks/cooker.rb`
- **Result**: `PASS` (`order_ok=true`, `distinct_wall=true`)

## Load (L1)

- `MERGE_FILES=60`
- `MERGE_LINES=80`
- `MERGE_FRAGMENTS=10`
- `SAMPLES=3`

## Gate

- **Command**: `env -u BUNDLE_PATH SCENARIO=gate MERGE_FILES=60 MERGE_LINES=80 MERGE_FRAGMENTS=10 SAMPLES=3 bundle exec ruby benchmarks/cooker.rb`

## Ceilings

- **File**: `benchmarks/ceilings.json` — **unchanged** (no widening during episode; tighten-only rule held).

## Final gate (prove)

- **Path**: `benchmarks/output/20261106160329_cooker_gate.json`
- **Pass**: **true**
- **Metrics (median, n=3)** vs ceiling:
  - `wall_s`: **0.011024** ≤ `0.01137614499639312` ✓
  - `cpu_s`: **0.013046** ≤ `0.013347762499999999` ✓
  - `allocated_objects`: **4396** ≤ `7950.98…` ✓
  - `storage_delta_bytes`: **115141** ≤ `128385.82…` ✓

## Iterations — optimize → prove

Primary series named per cycle; one main code change per cycle; prove = gate L1 (`SAMPLES=3`).

### Part A (cycles 1–10)

| # | Primary | Hypothesis / change | Prove |
|---|---------|---------------------|-------|
| 1 | `allocated_objects` | `File.binread`, `coverage_blob_from_doc`, single-nested `extract_coverage_blob` | fail |
| 2 | `wall_s` | `merge_two_into` ping-pong (experiment) | fail → **reverted** |
| 3 | `wall_s` | Full `merge_two` `rb_hash_foreach` (experiment) | fail → **reverted** |
| 4 | `wall_s` | C: secondary `rb_hash_foreach` + `rb_hash_new_capa` | fail |
| 5 | `allocated_objects` | C: cached `id_keys` / `id_plus` / `id_gt`; Fixnum line-hit `+` | fail |
| 6 | `allocated_objects` | `# frozen_string_literal`; meta path without per-row `JSON.generate` | fail |
| 7 | `allocated_objects` | Cooker: short paths + memoized frozen path strings | fail (time); alloc ok |
| 8 | `cpu_s` | `rb_hash_new_capa` for merge output | fail |
| 9 | `wall_s` | `RUBY_YJIT_ENABLE=1` (harness only) | fail |
| 10 | `allocated_objects` | C: empty secondary → `rb_hash_dup(primary)` | fail |

### Part B (cycles 11–16, continuation)

| # | Primary | Hypothesis / change | Prove |
|---|---------|---------------------|-------|
| 11 | `wall_s` | C: `rb_hash_foreach` on **primary** merge pass | fail → **reverted** (regressed `wall_s`) |
| 12 | `allocated_objects` | `merge_fragment_metas_from_metas`: return `{}` when every fragment meta is empty | fail (still red on time) |
| 13 | `allocated_objects` | C: one global frozen `"ignored"` string (`str_ignored`) instead of allocating per hit | fail (until paired with later steps) |
| 14 | `allocated_objects` | C: frozen singleton empty lines array for `coerce_line_array(NIL)` | fail |
| 15 | `wall_s` | C: `merge_line_arrays` uses `RARRAY_CONST_PTR` instead of `rb_ary_entry` per index | fail |
| 16 | `wall_s` | Cooker: `JSON.fast_generate` for fragment files; C: secondary pass back to indexed `keys` loop (drop `rb_hash_foreach` overhead on secondary) | **pass** ✓ |

**Accept**: **Yes** — after cycle 16 the gate is green at L1 with ceilings fixed; `allocated_objects` remains under ceiling.

## Key artifacts

- `ext/polyrun_coverage_merge/coverage_merge.c` — `str_ignored`, `ary_empty_lines`, `RARRAY_CONST_PTR` line merge, `rb_hash_new_capa`, cached IDs, Fixnum add fast path, empty-secondary fast path; secondary merge uses `keys` + indexed loop (not `rb_hash_foreach`).
- `lib/polyrun/coverage/merge_fragment_meta.rb` — early exit when all fragment metas are empty.
- `benchmarks/cooker.rb` — `JSON.fast_generate` for written fragments; short paths + path memoization.

## Release

- Cut into 2.2.9 (`docs/changelogs/20261107102709_release-2-2-9.md`).

## Tests

- `bundle exec rspec spec/polyrun/coverage/merge_native_spec.rb spec/polyrun/coverage/merge_spec.rb spec/polyrun/coverage/merge_formats_spec.rb` — green after final changes.

## Episode JSON

- `benchmarks/output/20261106162000_episode.json` — `accepted: true`, final gate path above.
