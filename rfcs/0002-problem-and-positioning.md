# RFC 0002: Problem and positioning

- Feature Name: problem-and-positioning
- Type: Informational
- Status: Stable
- Created: 2026-08-17
- Updated: 2026-08-18
- Author: Andrei Makarov
- Relates: RFC 0003, RFC 0004, RFC 0005, RFC 0006

## Summary

Polyrun plans and runs test shards, merges SimpleCov-compatible coverage fragments, and emits CI reports. The runtime graph is standard library and vendored code only.

## Motivation

Parallel test runs still need one merged coverage report, stable shard assignment, per-worker databases, and timing data. Teams otherwise wire a partition script, a coverage merge plugin, JUnit conversion, and database URL helpers, then discover those tools disagree on `POLYRUN_SHARD_INDEX`.

Local fan-out and CI matrix sharding are different layouts. `run-shards` and `parallel-rspec` spawn N workers on one machine. `ci-shard-run` and `ci-shard-rspec` run one global shard per CI job. Using the local commands in a matrix job double-partitions the suite. Hook names make that worse: `before_suite` in the parent is one orchestration on one host, and `ci-shard-run` skips suite hooks when `POLYRUN_SHARD_TOTAL` is greater than 1 unless `POLYRUN_HOOKS_SUITE_PER_MATRIX_JOB=1`.

Coverage merge is a file contract. Workers write `coverage/polyrun-fragment-*.json`. Merge must survive mixed encodings. The fragment schema, `POLYRUN_SHARD_*` environment, and `polyrun.yml` `partition` keys are what every host CI file depends on.

Per-worker databases and prepare hooks exist because shared rows and shared asset digests make parallel runs flake.

## Guide-level explanation

Add the gem, point `polyrun.yml` at partition and coverage settings, run `bin/polyrun run-shards` or `ci-shard-run` in CI, then merge coverage. `bin/polyrun build-paths` refreshes `partition.paths_file` from globs. `parallel-rspec` and `run-shards --merge-coverage` run merge after workers exit.

Hooks in `polyrun.yml` and `hooks.ruby` follow suite, shard, and worker phases. Set `POLYRUN_HOOKS_DISABLE=1` to skip orchestration hooks.

## Drawbacks

Operators must choose a layout per job and keep fragment paths stable. A no-extra-gems runtime means coverage formats Polyrun emits must stay in this gem.

## Rationale and alternatives

One development gem with no extra runtime gems keeps CI install graphs small. A host-local partition script plus SimpleCov merge plugins works until shard env, fragment names, and JUnit reporting drift. Polyrun does not replace Capybara or Playwright; those stay in the application.

## Prior art

parallel_tests, Knapsack, SimpleCov, and CI matrix sharding. Contract detail is RFC 0003 through RFC 0006.

## Unresolved questions

Whether `Polyrun::Quick` stays in this gem or moves to its own RFC when the DSL grows.

Whether hook suite behavior on CI matrix jobs should become a dedicated RFC separate from `polyrun.yml` partition keys (RFC 0005).
