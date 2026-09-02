# RFC 0004: Coverage merge

- Feature Name: coverage-merge
- Type: Standards Track
- Status: Stable
- Created: 2026-08-18
- Author: Andrei Makarov
- Relates: RFC 0002, RFC 0003

## Summary

Workers write SimpleCov-compatible JSON fragments. Merge reads `coverage/polyrun-fragment-*.json` as UTF-8 and emits JSON, LCOV, Cobertura, console, CSV, or Markdown.

## Motivation

Parallel runs are useless to a coverage gate unless one report exists. Fragment names and encoding are the file contract every CI job depends on. A silent rename or a locale-dependent read fails the gate.

## Guide-level explanation

Enable coverage so each worker writes a fragment keyed by `POLYRUN_SHARD_INDEX`. Merge with `bin/polyrun merge-coverage`, or `run-shards --merge-coverage`, or `parallel-rspec`.

`report-coverage` prints summaries. Default post-merge formats include `csv` and `markdown` (`POLYRUN_MERGE_FORMATS`). Optional native acceleration may exist with Ruby fallbacks.

`Polyrun::Quick` uses the same collector when `POLYRUN_COVERAGE=1` or `config/polyrun_coverage.yml` is present, and skips it when `POLYRUN_COVERAGE_DISABLE=1`.

## Reference-level explanation

Fragment glob: `coverage/polyrun-fragment-*.json`. Reads are UTF-8. `run-shards --merge-coverage` can fail the process when merged coverage is below `minimum_line_percent` unless strict is false in `polyrun_coverage.yml`.

## Registrar

CLI verbs: `merge-coverage`, `report-coverage`. Env: `POLYRUN_COVERAGE`, `POLYRUN_COVERAGE_DISABLE`, `POLYRUN_MERGE_FORMATS`. Glob: `coverage/polyrun-fragment-*.json`.

## Drawbacks

Fragment files must land in a shared `coverage/` directory. Native merge is optional; Ruby fallback must stay correct. Format list growth is a later RFC.

## Rationale and alternatives

SimpleCov's built-in merge assumes one process family and one encoding. A host-local merge script drifts on fragment names. Doing nothing leaves coverage gates on a single worker's slice.

## Prior art

SimpleCov JSON result files. LCOV and Cobertura as CI consumers. parallel_tests coverage merge plugins. RFC 0003 defines which workers wrote the fragments.

## Unresolved questions

Whether fragment schema should freeze before a second merge implementation appears.
