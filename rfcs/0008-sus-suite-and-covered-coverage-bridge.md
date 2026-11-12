# RFC 0008: Sus suite and Covered coverage bridge

- Feature Name: sus-suite-covered-bridge
- Type: Standards Track
- Status: Stable
- Created: 2026-11-12
- Author: Andrei Makarov
- Relates: RFC 0002, RFC 0003, RFC 0004, RFC 0007

## Summary

Add Sus as a first-class parallel suite (`partition.suite: sus`, path glob `test/**/*.rb`, `parallel-sus`, `ci-shard-sus`, `Polyrun::SusSupport`). Treat Covered-style `COVERAGE` as a coverage-wanted signal for the Polyrun collector so Sus hosts can write shard fragments without a second coverage gem in the Polyrun runtime graph.

## Motivation

Sus lists tests under `test/**/*.rb` and accepts path ARGV. Polyrun previously classified those paths as Quick and had no Sus suite. Covered enables reporting via `COVERAGE`; Polyrun only looked at `POLYRUN_COVERAGE`. Sus's in-process `sus-parallel` does not provide OS-process shards for per-worker databases.

## Guide-level explanation

```yaml
partition:
  suite: sus
```

```bash
bin/polyrun parallel-sus --workers 4
bin/polyrun ci-shard-sus
```

Auto-detect: when `config/sus.rb` exists and `test/**/*.rb` is non-empty, bare `polyrun` selects Sus (after RSpec files, before Minitest-only `*_test.rb` trees without Sus config).

In `config/sus.rb`:

```ruby
require "polyrun/sus_support"
Polyrun::SusSupport.install_parallel_provisioning!
Polyrun::SusSupport.install_coverage!
Polyrun::SusSupport.install_worker_ping!
```

Use either Polyrun `install_coverage!` or Covered::Sus in one process, not both, so `Coverage.start` is not contested. Shard merge stays on Polyrun JSON fragments.

## Reference-level explanation

- Allowed `partition.suite` values: `auto`, `rspec`, `minitest`, `sus`, `quick`
- Sus glob: `test/**/*.rb` (matches Sus `DEFAULT_TEST_PATTERN`)
- Auto-detect Sus when `config/sus.rb` is present and the Sus glob is non-empty
- Path family inference: `_spec.rb` → rspec; `_test.rb` → minitest; path under `test/` (not `polyrun_quick`) → sus; `polyrun_quick` or other `.rb` → quick; mixed families → invalid
- CLI: `parallel-sus` defaults to `bundle exec sus`; `ci-shard-sus` defaults to `bundle exec sus`
- `Coverage::Collector.coverage_requested_for_quick?` is true when `COVERAGE` is set to a non-falsey value (Covered report names included)
- Require path: `polyrun/sus_support`; constant: `Polyrun::SusSupport`

## Drawbacks

Hosts with both Sus config and Minitest-style `*_test.rb` under `test/` auto-select Sus. Explicit `partition.suite` overrides. Mixing path families in one run remains rejected.

## Rationale and alternatives

- Import Covered `.covered.db` (MessagePack): deferred; needs a vendored unpacker or a new runtime dependency
- Only document `ci-shard-run -- bundle exec sus`: cheap, leaves path inference wrong for Sus layouts
- Thread-only Sus parallel: does not isolate shard databases

## Prior art

Sus file ARGV filtering and Covered `COVERAGE` activation. Polyrun OS-process sharding for RSpec, Minitest, and Quick.

## Unresolved questions

Whether SpecQuality per-example hooks for Sus need a dedicated installer beyond WorkerPing suite hooks.

## Future possibilities

Optional `.covered.db` → Polyrun fragment conversion without adding a registry dependency. Named init profile for Sus hosts.
