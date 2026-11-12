# Sus suite and Covered coverage bridge

## Decisions

Ship RFC-0008: first-class Sus suite and Covered `COVERAGE` bridge for Polyrun collector enablement.

## Effects

- `partition.suite: sus`, `parallel-sus`, `ci-shard-sus`, path glob `test/**/*.rb`, auto-detect via `config/sus.rb`
- `Polyrun::SusSupport` installers for provisioning, coverage fragments, worker ping
- Sus-style paths no longer classify as Quick
- Non-falsey `COVERAGE` enables coverage-wanted gates

## Next

- Iteration 2 audit after specs: SpecQuality Sus hooks, `.covered.db` import without new runtime gems

## Source

- `rfcs/0008-sus-suite-and-covered-coverage-bridge.md`
- `docs/reviews/20261112153400_sus-covered-engineering-audit.md`
