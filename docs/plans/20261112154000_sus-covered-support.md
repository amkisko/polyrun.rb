# Plan: Sus suite and Covered bridge

## Decisions

Implement RFC-0008 on `feature/sus-covered-suite`. Keep runtime graph free of Sus and Covered gems; hosts supply those. Prefer OS-process `parallel-sus` for shard databases over Sus in-process thread fan-out.

## Effects

Code and docs for Sus suite + Covered env bridge landed with focused specs.

## Next

- Run partition, collector, SusSupport, and CLI registry specs
- Second audit pass for dual Coverage.start and SpecQuality gaps

## Source

- `rfcs/0008-sus-suite-and-covered-coverage-bridge.md`
- Sus `test/**/*.rb` + ARGV paths; Covered `COVERAGE` + optional `.covered.db`
