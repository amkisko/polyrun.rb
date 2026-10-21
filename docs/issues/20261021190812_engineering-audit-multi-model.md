# Engineering audit (multi-model) for polyrun.rb

## Decisions

Confirm and ship smallest credible fixes for high-certainty correctness and operability bugs found by four parallel model audits (core CLI/database, concurrency/queue, hot-path/coverage, tests/ownership). Defer structural work that needs a journal, process-group rewrite, or CLI command-object split to follow-up issues.

## Effects

Audit agents: Claude Sonnet (core), GPT (concurrency), Grok (hot-path), Gemini (tests/ownership). Findings fact-checked against lib/ and specs before implementation.

Confirmed for this release (observed in code, then fixed):

1. start argv parser ignores --workers=N while run-shards OptionParser accepts it, so shard DB count can disagree with worker count.
2. Implicit path run treated path-like tokens after -- as suite paths and appended --paths-file after --, so the worker command was emptied or ignored the paths file.
3. SpecQuality Report minimum_unique_lines_per_example gate only counts zero-hit examples.
4. SpecQuality Profile.diff overwrites its positive-or-cpu filter with an unconditional assignment.
5. Coverage ExampleDiff.collect_diff_paths uses Array#include? over peek keys (quadratic per example).
6. Plan and queue_weight_for file-granularity keys use File.expand_path while timing load uses TimingKeys.normalize_locator (realpath), so costs miss under symlinked roots.
7. TimingDiagnostics file-granularity stale scan uses Array#include? instead of Set.
8. run-queue accepts workers <= 0 (false green) and uses exit in fork (at_exit in child).
9. shard_db_pattern without %{shard} can name every shard the same DB or collide with template_db under DROP.
10. template_prepare_env_shell_log prints DATABASE_URL passwords on dry-run.
11. Config.load returns {} for an explicit missing path.
12. run-shards signal shutdown drains WorkerOutput pipes before TERM (join can hang while children live).
13. FileStore#claim! writes an empty lease when pending is drained.
14. Coverage::Rails and SpecQuality::Config YAML loaders disagree with Config.load on aliases/symbols.

Deferred (documented, not fixed here):

- FileStore multi-file claim/ack without write-ahead recovery.
- Lease reclaim by claimed_at without heartbeat (active work can be stolen).
- Batch-level ack re-runs successful paths after poison failure.
- Process group for worker trees; mid-spawn rescue for partial worker sets.
- CLI mixin flat namespace and duplicated cost/strategy loaders.
- HTML merge N+1 ERB compile; merge fragment peak retention.
- Futile private .send unit specs cleanup.

## Next

- Ship 2.2.6 with the confirmed fixes and changelog.
- Open follow-ups for queue journal + lease heartbeat and worker process groups if operators hit those paths.
- Replace collector_finish_unit_spec .send examples with public Collector.finish coverage when touching that area.

## Source

- Multi-model audit session on polyrun.rb at VERSION 2.2.5 (Unreleased already held non-Postgres CloneShards notes).
- Prior related notes: docs/issues/20260928121826_non-postgres-clone-shards-on-start.md, docs/issues/20260907141000_engineering-and-dependency-audit.md.
