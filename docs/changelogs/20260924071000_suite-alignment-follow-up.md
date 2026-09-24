# Suite selection follow-up fixes

## Decisions

`parallel-minitest` and `parallel-quick` match `parallel-rspec`: run-shards plus merge-coverage only. Prepare and database bootstrap stay on `polyrun start` and bare `polyrun` default dispatch. Legacy `spec/spec_paths.txt` is skipped when `partition.suite` is `minitest` or `quick`. Suite inference strips `path:line` locators. Mixed path lists are rejected only when the command after `--` is a known single-suite runner. Command detection uses runner basenames (`bin/rails`) and compact `-Itest`.

## Effects

Explicit parallel subcommands no longer execute configured shell prepare or replace shard databases. Mismatch guard catches common Rails binstubs. Explicit non-RSpec suite selection works in repos that still have a legacy RSpec paths file. Example-granularity path lists reach RSpec again. Custom `run-shards -- <command>` runners can still receive mixed lists.

## Next

None.

## Source

Follow-up to `docs/changelogs/20260923222000_suite-paths-file-alignment.md`.
