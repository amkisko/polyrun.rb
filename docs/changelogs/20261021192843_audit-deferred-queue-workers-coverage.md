# Audit deferred follow-up: queue, workers, coverage

## Decisions

Implement the deferred items from docs/issues/20261021190812_engineering-audit-multi-model.md except the full CLI mixin command-object rewrite. Prefer smallest durable fixes (intent file, heartbeat age, isolate-on-failure, pgroup, ERB cache, shared cost helper).

## Effects

- Queue FileStore: intent recovery, done-before-lease-drop ack, heartbeat, path_attempts quarantine, ack_paths!
- WorkerLoop: batch success path unchanged; failure isolates per path
- run-shards: pgroup spawn, group signals, mid-spawn terminate
- Coverage: HTML ERB cache, merge_fragments meta/blob extract; collector_finish_unit_spec removed
- CLI: partition_resolve_costs_and_strategy shared by plan and run-shards

## Next

- Tag 2.2.6 when ready
- CLI command-object split remains optional

## Source

- docs/issues/20261021190812_engineering-audit-multi-model.md
- Fact-check subagent on deferred plan
