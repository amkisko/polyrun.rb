# Native graph and quality commands

## Participants

Andrei Makarov (@amkisko).

## Decisions

Implement experimental RFC-0010 within Polyrun using Ruby standard libraries and no runtime package dependencies.

## Effects

Add native graph indexing, conservative call inspection, staged call-name edits, syntax and optional behavioral checks, approval receipts, and journaled apply recovery under .polyrun/graph.

Add native mutation generation with extensible literal, operator, and method-body operators. Run a baseline and isolated per-mutation tests with deterministic subject sharding, bounded workers, and incomplete-result handling.

Add explicit opt-in and shared root, feature, and suite settings for graph, mutation, observation, measurement, and per-example quality. Expose resource budgets, source and staging filters, commands, operators, and outputs through validated configuration.

Add bounded Ruby call observation and command measurement. Document resource limits, trust boundaries, and report semantics in docs/QUALITY.md. Add executable coverage and a standalone packaged-gem check. This entry describes uncommitted implementation work, not a published release.

## Next

Evaluate consuming projects before promoting the experimental interfaces.

## Source

- ../QUALITY.md.
- ../../rfcs/0010-graph-and-quality-orchestration.md.
- ../reviews/20261114104846_graph-and-mutation-engineering-audit.md.
