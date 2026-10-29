# Engineering audit fixes for 2.2.6

## Participants

Andrei Makarov (@amkisko)

## Decisions

Ship the confirmed high-certainty fixes from the multi-model engineering audit; leave queue journal, lease heartbeat, and process-group work for follow-up.

## Effects

- Implicit path runs split argv at `--` before classifying paths, and insert `--paths-file` before `--`.
- `start` accepts `--workers=N`; run-queue rejects workers outside 1..MAX and uses `exit!` in fork children.
- SpecQuality gate for `minimum_unique_lines_per_example` and Profile.diff positive-or-cpu filter behave as named.
- Plan / queue file-granularity cost keys use `TimingKeys.normalize_locator`; ExampleDiff path union is linear; TimingDiagnostics stale scan uses Set.
- `shard_db_pattern` must include a shard placeholder and must not resolve to `template_db`; dry-run DB env logs redact passwords.
- Explicit missing config path raises; CLI maps `Polyrun::Error` to exit 2.
- Signal shutdown TERMs workers before draining WorkerOutput; empty queue claims do not create leases.
- Coverage Rails and SpecQuality YAML loaders use `safe_load_file` with Symbol and aliases.

## Next

- Cut recorded in `docs/changelogs/20261029102014_release-2-2-6.md`. Push `main` and run `make release` for tag and RubyGems publish.
- Follow-ups listed in docs/issues/20261021190812_engineering-audit-multi-model.md.

## Source

- docs/issues/20261021190812_engineering-audit-multi-model.md
- Prior Unreleased notes: docs/changelogs/20260928121826_non-postgres-clone-shards-on-start.md
