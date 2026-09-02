# RFC 0003: Shard layouts

- Feature Name: shard-layouts
- Type: Standards Track
- Status: Stable
- Created: 2026-08-18
- Author: Andrei Makarov
- Relates: RFC 0002, RFC 0005, RFC 0006

## Summary

Polyrun has two parallel layouts. `run-shards` and `parallel-rspec` spawn N workers on one machine. `ci-shard-run` and `ci-shard-rspec` run one global shard per CI job. Mixing them double-partitions the suite.

## Motivation

CI matrix jobs each receive `POLYRUN_SHARD_INDEX` and `POLYRUN_SHARD_TOTAL` for the pipeline. A job that then calls `run-shards --workers N` partitions that slice again. Coverage and timing reports then describe a different file set than the matrix cell.

## Guide-level explanation

Local fan-out: `bin/polyrun run-shards --workers N -- bundle exec rspec`. `parallel-rspec` is `run-shards` with merge-coverage and a default RSpec command.

CI matrix: `bin/polyrun ci-shard-run -- …` or `ci-shard-rspec`. Pass `--shard` and `--total` or rely on `POLYRUN_SHARD_*`. Optional `--shard-processes M` fans out M local processes inside one matrix cell and sets `POLYRUN_SHARD_MATRIX_*` on children when both matrix N and local M are greater than 1.

`plan` writes the file list for a layout. `start` prepares then runs workers. `queue` / `run-queue` are an on-disk work queue for the same path list.

## Reference-level explanation

Worker environment includes `POLYRUN_SHARD_INDEX` and `POLYRUN_SHARD_TOTAL` for that layout. `ci-shard-run` without `--` exits 2. Empty command after `--` exits 2. `--shard-processes` must be an integer. Local layout commands MUST NOT be the default inside a matrix cell that already set `POLYRUN_SHARD_TOTAL` greater than 1.

## Registrar

CLI verbs: `run-shards`, `parallel-rspec`, `ci-shard-run`, `ci-shard-rspec`, `plan`, `start`, `queue`, `run-queue`. Env: `POLYRUN_SHARD_INDEX`, `POLYRUN_SHARD_TOTAL`, `POLYRUN_SHARD_MATRIX_*`.

## Drawbacks

Operators must pick one layout per job. Nested fan-out (`--shard-processes`) adds a second pair of env names to document.

## Rationale and alternatives

One command for local and CI would double-partition by accident. A host-local partition script plus `CI_NODE_INDEX` drifts from `POLYRUN_SHARD_*`. Doing nothing leaves each CI file to invent shard env.

## Prior art

Knapsack, parallel_tests, and CI `matrix.shard` patterns. SimpleCov parallel merge assumes one partition of the suite. RFC 0004 merges coverage for whichever layout ran. RFC 0005 skips suite hooks on matrix jobs.

## Unresolved questions

Whether `POLYRUN_SHARD_MATRIX_*` names should freeze as a dedicated env registrar.
