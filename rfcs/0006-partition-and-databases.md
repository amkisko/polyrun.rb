# RFC 0006: Partition config and databases

- Feature Name: partition-and-databases
- Type: Standards Track
- Status: Stable
- Created: 2026-08-18
- Author: Andrei Makarov
- Relates: RFC 0002, RFC 0003

## Summary

`polyrun.yml` holds partition paths, shard index and total, strategy, optional database templates, prepare recipes, and coverage settings. Per-worker databases exist so parallel workers do not share rows.

## Motivation

A host-local partition script plus `DATABASE_URL` edits drift from `POLYRUN_SHARD_*`. Polyrun owns path lists and shard database URLs in one file. Changing `partition` keys or `shard_db_pattern` without a numbered RFC breaks CI that already generated those URLs.

## Guide-level explanation

Point `bin/polyrun` at `polyrun.yml` or pass `-c`. Configure `partition` (paths, shard index and total, strategy). Optional `partition.paths_build` writes `partition.paths_file` from globs and ordered stages (`bin/polyrun build-paths`).

Optional `databases` uses a Postgres template and `shard_db_pattern`. CLI helpers: `db:setup-template`, `db:setup-shard`, `db:clone-shards`. `run-shards` merges polyrun.yml database URLs per shard.

Prepare runs before fan-out. `start` can skip prepare with `POLYRUN_START_SKIP_PREPARE=1`.

## Reference-level explanation

`plan` exits 2 when there are no paths and no `paths_file`. Shard database URLs come from `shard_db_pattern` plus shard index. Coverage settings in this file feed RFC 0004. Hooks in this file feed RFC 0005.

## Registrar

YAML keys: `partition`, `databases`, `prepare`, `coverage`, `hooks`. CLI: `build-paths`, `prepare`, `db:setup-template`, `db:setup-shard`, `db:clone-shards`, `config`, `env`.

## Drawbacks

One YAML file becomes the CI contract. Postgres templates are optional and host-specific. Empty path lists fail closed rather than running the whole suite.

## Rationale and alternatives

Environment-only shard config would skip path files and would still need a database URL builder. Letting each worker share one database is simpler and flakes on rows. Doing nothing leaves `DATABASE_URL` edits in CI YAML.

## Prior art

parallel_tests database numbering. Knapsack path files. Rails `DATABASE_URL` per process. RFC 0003 consumes the path list this file defines.

## Unresolved questions

Whether `partition.paths_build` stage syntax should freeze as a dedicated file contract.
