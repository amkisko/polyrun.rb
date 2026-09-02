# RFC 0005: Orchestration hooks

- Feature Name: hooks
- Type: Standards Track
- Status: Stable
- Created: 2026-08-18
- Author: Andrei Makarov
- Relates: RFC 0002, RFC 0003

## Summary

Hooks run around Polyrun orchestration, not around RSpec example groups. Suite and shard hooks run in the parent. Worker hooks run in the child. CI matrix jobs skip suite hooks when `POLYRUN_SHARD_TOTAL` is greater than 1 unless `POLYRUN_HOOKS_SUITE_PER_MATRIX_JOB=1`.

## Motivation

Hosts put expensive global setup in `before_suite`. If every matrix cell ran suite hooks, that setup would run once per shard.

## Guide-level explanation

Declare shell commands under `hooks:` in `polyrun.yml`, or a Ruby DSL file in `hooks.ruby`. YAML keys: `before_suite`, `after_suite`, `before_shard`, `after_shard`, `before_worker`, `after_worker`. DSL names: `before(:suite)`, `after(:suite)`, `before(:all)` (shard), `after(:all)`, `before(:each)` (worker), `after(:each)`.

For one phase, all Ruby blocks run first, then YAML shell commands. `bin/polyrun hook run PHASE` runs a phase from CI. `POLYRUN_HOOKS_DISABLE=1` skips orchestration hooks; `hook run` still executes.

Parent waits workers in shard index order, so `after_shard` runs 0 then 1, not finish order.

## Reference-level explanation

Environment includes `POLYRUN_HOOK_PHASE`, `POLYRUN_HOOK=1`, `POLYRUN_HOOK_ORCHESTRATOR` (`1` parent, `0` worker), `POLYRUN_SHARD_*`, and `POLYRUN_SUITE_EXIT_STATUS` on `after_suite`. Worker children get `POLYRUN_HOOKS_RUBY_FILE` when using the Ruby DSL. `after_worker` shell steps must not mask the test exit code.

## Registrar

Hook phase names listed above. Env: `POLYRUN_HOOKS_DISABLE`, `POLYRUN_HOOKS_SUITE_PER_MATRIX_JOB`.

## Drawbacks

DSL names `before(:all)` and `before(:each)` look like RSpec and mean shard and worker. Matrix skip surprises hosts who expected suite hooks on every job.

## Rationale and alternatives

Running suite hooks on every matrix cell would repeat global setup. Mapping hook names to RSpec example hooks would run them inside workers and break parent-only setup. Doing nothing leaves CI YAML to duplicate `before_suite`.

## Prior art

RSpec `before(:suite)` and parallel_tests worker hooks. GitHub Actions job-level setup versus matrix-cell setup. RFC 0003 is the layout that sets `POLYRUN_SHARD_TOTAL`.

## Unresolved questions

Whether hook suite behavior on CI matrix jobs should split from partition keys into a dedicated follow-on RFC.
