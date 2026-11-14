# RFC 0010: Graph and quality orchestration

- Type: Standards Track
- Status: Experimental
- Created: 2026-11-14
- Author: Operator (name awaiting confirmation)

## Summary

Implement Ruby graph indexing, guarded graph edits, native mutation testing, observation, and bounded command measurements inside Polyrun using Ruby standard libraries. Existing partition, coverage, timing, and benchmark commands remain available.

## Motivation

A single installation should inspect Ruby structure, prepare a small verified edit, run behavioral checks against the staged project, and evaluate whether tests detect source changes. Requiring an independent graph service or mutation package would prevent that workflow from being self-contained.

## Guide-level explanation

The command workflow and its limits have one maintained home in [docs/QUALITY.md](../docs/QUALITY.md). Graph operations use nested verbs so the existing partition `plan` command keeps its contract. Mutation commands take explicit subjects and a test command after `--`. No compatibility executable aliases or external engine settings are accepted.

## Reference-level explanation

Prism parses source without evaluating project code. A bounded JSON index under `.polyrun/graph` records method and call nodes, source hashes, byte locations, and conservative edge provenance. Exact subjects and unique selectors prevent ambiguous edit targets. The initial edit operation replaces a selected call name after verifying its token and fingerprint.

Plans stage the project, verify syntax, and retain the expected source and staged hashes. Successful checks bind all staged bytes to a local receipt. Optional behavioral proof runs against the staged Gemfile and library directory. Apply verifies the receipt and original inventory, then writes through a backup journal and per-file replacement. Recovery refuses to overwrite outside changes. Neither a local receipt nor the journal is a security signature or whole-tree atomic commit.

The mutation engine selects method definitions, generates deduplicated syntax-valid edits with extensible operator objects, and runs a clean baseline. Every mutation gets a fresh copy and a bounded test subprocess. Exit 0 survives, exit 1 kills, and infrastructure failures remain incomplete. Deterministic subject sharding and bounded local workers compose with CI. Default and absolute resource limits are documented with the commands.

The command runner controls process groups, time, and output. Observation records only bounded local call evidence. Measurement distinguishes command wall time, CPU counters, and orchestrator memory. The pressure harness separately probes process-lifetime RSS; it does not claim stage RSS or energy savings.

## Configuration and activation

Graph, mutation, observation, and measurement commands default to disabled. Enable each feature in polyrun.yml, use its explicit environment switch, or pass --enable for one invocation. --no-enable overrides configured activation. Global settings never activate features. Direct Ruby API calls are explicit opt-in and accept a settings mapping.

Resolve settings in this order: command-line overrides, environment, suite-merged feature configuration, shared defaults at the YAML root, built-in defaults. Each shared setting has one root location; a global section is not accepted. POLYRUN_WORKERS overrides configured worker defaults for both mutation and existing parallel commands. The existing --config and --suite mechanisms apply to the new tools. A command's --root also selects project-local automatic configuration discovery.

Root shared defaults and the graph, mutation, and quality sections have validated keys and types. Quality has observe, measure, and spec_quality sub-sections. Defaults, merging, and validation remain independent from execution. Resource limits, source and staging filters, graph state location, commands, subjects, operator selection, report outputs, and quality thresholds can be set without editing Ruby. Invalid settings fail before side effects. Effective settings are available through polyrun config and checked by polyrun validate.

## Security considerations

Indexing does not execute the project. Tests, mutation probes, and prove commands execute trusted project code with the caller's authority. Project copies are not OS sandboxes. Path validation, symlink rejection, freshness checks, and a workspace lock protect the cooperative local workflow. Output may contain project diagnostics and paths. No remote telemetry or persistent device identifiers are introduced.

## Drawbacks

A fresh process and project copy for each mutation repeats test startup and consumes bounded temporary storage. The initial mutation operators and static graph inference cover a deliberately limited Ruby contract. Dynamic dispatch remains uncertain. Experimental status remains until consuming projects exercise the workflow.

## Decisions

Keep all runtime implementation inside Polyrun with no new package dependency. Use Prism, JSON, safe YAML, Ruby threads, process groups, and ordinary host processes. Keep graph storage rebuildable from source; plans and approvals must be recreated after deletion. Do not add a compatibility layer for earlier unshipped interfaces.

## Unresolved questions

Broader mutation operators, richer graph edits, and larger project-copy ceilings require consuming-project evidence and separate contract decisions.
