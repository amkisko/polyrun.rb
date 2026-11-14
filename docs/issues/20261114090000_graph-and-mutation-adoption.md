# Native graph and mutation implementation

## Participants

Andrei Makarov (@amkisko).

## Decisions

Implement RFC-0010 with Polyrun's own graph and mutation engines, terminology, and state. Keep Ruby standard libraries first and add no runtime dependency. Include bounded staged proof, observation-based subject selection, measurements, iterative engineering review, and pressure trials. Preserve unrelated release work and pre-existing local data.

The native workload replaces the earlier unshipped benchmark contract. Establish a new calibrated baseline for actual graph indexing and mutation execution; previous protocol-fixture timings are not comparable. Record any new ceiling proposal explicitly before pressure trials, then keep it fixed throughout those trials.

The follow-up activation contract supersedes the earlier unshipped implicit command activation: graph, mutation, observation, and measurement now require explicit opt-in. Shared root and feature settings own configurable budgets and commands.

Curated self-mutation literal and body undetected cases were assessed: detectable suite gaps closed, one redundant key-name check removed, two behavioral equivalents accepted, and the CI gate kept on the operator family. RFC-0010 stays Experimental until a hosted consuming app runs graph check or mutate in its own CI.

## Effects

Implementation, the standalone package check, the native pressure episode, and final whole-suite validation are complete. The command guide owns operational contracts. The review record owns findings and exact validation commands. Raw measurements and cycle decisions belong in benchmarks/quality-episode.json. This checkout runs graph index, curated mutation, observe, and measure through make quality-self and the quality CI job. Undetected-mutation and consumer assessment evidence is in the 20261114182832 review. Relative --root expansion no longer doubles the selected project path. No release, publication, or commit is performed by this work.

## Next

Run graph check or mutate in a hosted consuming application's CI with that application's ordinary test command before promoting RFC-0010 off Experimental.

## Source

- ../../rfcs/0010-graph-and-quality-orchestration.md.
- ../QUALITY.md.
- ../reviews/20261114104846_graph-and-mutation-engineering-audit.md.
- ../reviews/20261114141417_configurable-quality-tools.md.
- ../reviews/20261114150543_root-config-defaults.md.
- ../reviews/20261114161158_self-graph-and-mutation.md.
- ../reviews/20261114182832_undetected-mutation-and-consumer-assessment.md.
- ../../benchmarks/quality-binding.md.
