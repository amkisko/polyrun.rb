# Engineering audit (multi-model) for polyrun.rb

## Decisions

Confirm and ship smallest credible fixes for high-certainty correctness and operability bugs found by four parallel model audits (core CLI/database, concurrency/queue, hot-path/coverage, tests/ownership). Follow-up batch implements deferred queue durability, worker process groups, coverage merge/HTML, cost-loader dedupe, and collector finish public specs. Full CLI mixin command-object rewrite stays deferred (large ownership change, low immediate danger).

## Effects

Audit agents: Claude Sonnet (core), GPT (concurrency), Grok (hot-path), Gemini (tests/ownership). Findings fact-checked against lib/ and specs before implementation. Follow-up batch fact-checked again ([deferred fixes](c617f93e-04d5-453f-8c26-51929d015b84)) before coding.

Confirmed for 2.2.6 first pass (observed in code, then fixed):

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

Follow-up batch (this session):

15. FileStore claim/ack/reclaim write intent.json (fsync) and recover incomplete ops under flock; ack writes done.jsonl before dropping the lease.
16. Lease reclaim ages heartbeat_at (fallback claimed_at); heartbeat! refreshes active work; path_attempts.json + failed.jsonl quarantine after POLYRUN_QUEUE_MAX_ATTEMPTS (default 3).
17. WorkerLoop keeps one-shot successful batches; on failure re-runs paths one-by-one with ack_paths! so passing paths are not requeued with a poison neighbor.
18. Worker Process.spawn uses pgroup: true; TERM/KILL targets the process group with pid fallback; mid-spawn StandardError/ScriptError terminates already-started workers; WorkerOutput closes pipes if spawn raises.
19. HTML merge caches ERB templates; merge_fragments extracts meta then blobs without retaining full JSON documents through the tree fold.
20. plan and run-shards share partition_resolve_costs_and_strategy; collector_finish_unit_spec (.send) replaced by public Collector.finish in-process examples.

Still deferred:

- Full CLI mixin flat-namespace rewrite into per-command objects (ownership only; behavior covered elsewhere).

## Next

- Keep VERSION/CHANGELOG on 2.2.6 until tagged; include follow-up bullets in the 2.2.6 notes.
- Tag and publish when the tree is clean and usr/bin/release.rb checks pass.
- Revisit CLI command-object split only if mixin coupling blocks a concrete change.

## Source

- Multi-model audit session on polyrun.rb at VERSION 2.2.5; follow-up on patch/engineering-audit-fixes.
- Prior related notes: docs/issues/20260928121826_non-postgres-clone-shards-on-start.md, docs/issues/20260907141000_engineering-and-dependency-audit.md.
- Engineering changelog: docs/changelogs/20261021191449_engineering-audit-fixes.md
