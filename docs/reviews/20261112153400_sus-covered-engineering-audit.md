# Engineering audit: Sus suite and Covered coverage bridge

## Decisions

Audit partition and coverage ingress for Sus (process-sharded file lists) and Covered (`COVERAGE` activation, persist database). Implement first-class `partition.suite: sus`, path globs `test/**/*.rb`, CLI `parallel-sus` / `ci-shard-sus`, `Polyrun::SusSupport`, and treat a set `COVERAGE` env as coverage-wanted for the Polyrun collector.

## Effects

Findings below drove iteration 1. Iteration 2 re-checks after the suite lands.

## Next

- Land Sus suite + Covered env bridge with specs.
- Re-audit: dual Coverage.start with Covered::Sus, MessagePack `.covered.db` import without new runtime gems, SpecQuality hook depth for Sus.

## Source

- Sus `DEFAULT_TEST_PATTERN` = `test/**/*.rb`; ARGV paths filter the registry; `config/sus.rb`; in-tree `sus-parallel` is thread fan-out inside one process.
- Covered activates on `COVERAGE`; optional persist to `.covered.db` (MessagePack); Sus include `Covered::Sus`.

## Findings

### F1 Mixed Sus-style paths classified as Quick

| Field | Content |
|-------|---------|
| Severity | High for Sus hosts; medium otherwise |
| Confidence | High |
| Location | `lib/polyrun/partition/paths.rb` `infer_suite_from_paths` |
| Why it matters | `test/foo.rb` (Sus layout) becomes `:quick`, so bare `polyrun` and implicit path runs dispatch the wrong runner |
| Kind | Observed fact |
| Smallest credible fix | Classify `test/**/*.rb` without `_test.rb` / `_spec.rb` and outside `polyrun_quick` as `:sus`; keep Quick for `polyrun_quick` and other `.rb` |

### F2 No Sus suite in partition contract

| Field | Content |
|-------|---------|
| Severity | High for Sus adopters |
| Confidence | High |
| Location | `Partition::Paths`, `Partition::Suite`, `CLI::DefaultRun`, `parallel-*` |
| Why it matters | Sus accepts path ARGV and needs OS-process shards for DB isolation; thread-only `sus-parallel` does not replace that |
| Kind | Observed fact |
| Smallest credible fix | Add `sus` to allowed suites, glob `test/**/*.rb`, auto-detect when `config/sus.rb` exists, `parallel-sus` / `ci-shard-sus` |

### F3 Covered `COVERAGE` ignored by Polyrun collector gates

| Field | Content |
|-------|---------|
| Severity | Medium |
| Confidence | High |
| Location | `Coverage::Collector` `coverage_requested_for_quick?` / enablement |
| Why it matters | Hosts that only set `COVERAGE` (Covered convention) never start Polyrun fragments under Quick/Sus helpers |
| Kind | Observed fact |
| Smallest credible fix | Treat non-empty `COVERAGE` (except falsey `0`/`false`/`no`/`off`) as coverage requested unless Polyrun disable flags are set |

### F4 Covered persist database not mergeable as Polyrun fragments

| Field | Content |
|-------|---------|
| Severity | Medium |
| Confidence | High |
| Location | Coverage merge ingress |
| Why it matters | `.covered.db` is MessagePack; Polyrun merge expects JSON fragments. Dual `Coverage.start` if both Covered::Sus and Collector run |
| Kind | Observed fact |
| Smallest credible fix | Document one collector per process; SusSupport `install_coverage!` uses Polyrun Collector for shard merge. Defer `.covered.db` import (needs MessagePack or a vendored unpacker) |

### F5 Boundary mode

Skipped for physical actuators. External surface is process spawn + env + coverage files. Risk: two coverage systems both calling `Coverage.start` in one worker.

## Pipeline map

```text
ingress (partition.suite / paths / COVERAGE)
  -> suite resolve
  -> shard plan
  -> worker spawn (sus + path list)
  -> coverage fragment write
  -> merge-coverage egress
```

## Modes run

- Core eight dimensions: yes
- Resource and budget: light (no new hot-path claim without bench)
- Trace and identification: skip (no new person identifiers)
- Boundary and control: process/env only, noted in F5
- Product-surface / privacy / security companions: skip (CLI contract only)
