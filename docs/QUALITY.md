# Graph edits and quality checks

Polyrun implements Ruby graph indexing, guarded source edits, mutation generation, execution, observation, and command measurements within the gem. These commands use Ruby standard libraries, including Prism. No additional graph or mutation package, executable, source checkout, or database is required. The consuming project's test command still needs its ordinary dependencies.

The commands are opt-in. See [Quality configuration](QUALITY_CONFIGURATION.md) for activation, shared defaults, per-feature settings, and every configurable limit.

## Graph workflow

    polyrun graph --enable index --json
    polyrun graph --enable inspect 'Account#save' --calls --callers --callees --json
    polyrun graph --enable inspect --control-plane --json
    polyrun graph --enable plan change.json --json
    polyrun graph --enable check PLAN --json --prove -- bundle exec rspec
    polyrun graph --enable apply PLAN --json

Every graph command accepts `--root PATH` and `--timeout SECONDS`. State lives under `.polyrun/graph`. Indexing parses source without executing it. It scans `lib` and `app` when present; otherwise it scans the project excluding development artifacts. The JSON index reuses unchanged source snapshots. Method identifiers, call identifiers, byte ranges, source fingerprints, and provenance describe the indexed source. Statically resolved edges are labeled `static_guess`; dynamic dispatch remains `unknown`. Lifecycle and signal inspection is a naming heuristic, not proof of runtime control flow.

Selectors accept an exact subject such as `Account#save` or `Account.build`, a node identifier, or `path:lib/account.rb#save`. A bare method name must resolve uniquely. Ambiguous selectors fail rather than choosing a definition.

A change description is JSON or safe YAML:

```json
{
  "snapshot": "snapshot-HASH",
  "operations": [{
    "op": "replace_call_name",
    "node": "call-ID",
    "expect": {"name": "old_name", "fingerprint": "HASH"},
    "replacement": "new_name"
  }]
}
```

Take the snapshot and call fields from index and inspect output. Planning supports this operation only, with a default ceiling of 1,000 distinct call edits. It validates expected tokens, applies byte edits to an isolated project copy, checks Ruby syntax, and emits a bounded diff. It does not rename every definition or infer dispatch equivalence.

Check verifies source freshness, syntax, and the intended staged hashes. An optional prove command runs in the staged tree; its Gemfile and library path point there. Tests that explicitly load an outside checkout cannot prove the staged edit. A successful check creates a receipt binding metadata and all staged files. A failed prove revokes previous approval. Apply rejects missing receipts, changed staged files, changed originals, added source files, symbolic links, and overlapping graph commands.

Apply uses per-file atomic replacement with backups and a recovery journal. An ordinary write failure restores originals. If the process stops during apply, the next apply attempts recovery before checking freshness. Recovery refuses to overwrite an unrelated edit. This is a cooperative local editing protocol; it does not provide a whole-tree atomic filesystem commit, protection from concurrent non-cooperating writers, or certified power-loss durability.

Rebuild a deleted index from source with `graph index`. Recreate deleted plans from the change description and check them again; receipts cannot be reconstructed as approvals.

## Mutation testing

    polyrun mutate --enable --subject 'Account#save' --workers 2 --timeout 120 -- bundle exec rspec
    polyrun mutate --enable --subjects-file subjects.txt --shard 1 --total 3 -- ruby -Ilib test/probe.rb
    polyrun mutate --enable --plan PLAN --max-mutations 1000 -- ruby -Ilib test/probe.rb
    polyrun mutate --enable --observed tmp/observed.json -- ruby -Ilib test/probe.rb

Arguments after `--` are the actual test command. Polyrun generates syntax-valid mutations of literals, comparison and arithmetic operators, and method bodies using Prism. The Ruby API accepts operator objects implementing `call(node)` for extension. This initial operator set does not cover every Ruby construct or establish semantic equivalence.

Subjects are exact method subjects or wildcard patterns using `*`. Subjects are deduplicated and sorted before deterministic one-based sharding. Missing or ambiguous definitions fail. There is no implicit whole-program run. Empty CI shards succeed with zero results. Plan selection targets methods containing the planned calls; it does not apply the plan first. Observed selection requires a complete observation.

A successful baseline runs before mutations in a separate project copy. Each unique mutation then runs in a fresh isolated copy, with one source edit. Exit 0 means survived; exit 1 means killed. Timeouts, excessive output, unavailable commands, signals, and other exit statuses are incomplete results and never kills. Any survivor or incomplete result fails the invocation. The command's exit-status contract matters: a test runner that uses exit 1 for unrelated setup errors cannot distinguish those errors from test failures.

The default worker ceiling is 32. The default mutation ceiling is 1,000; both are configurable. Each command defaults to a 300-second timeout and 1 MiB combined output; retained diagnostics are limited to 16 MiB. Default project staging permits at most 10,000 regular files and 64 MiB, with at most 1 GiB cumulative copied bytes per mutation invocation. Hidden directories, dependency caches, build outputs, symbolic links, and key files are excluded. Projects depending on excluded inputs need an explicit self-contained test setup.

The JSON report names the Polyrun engine, baseline, selected subjects, executed mutations, per-case result, and aggregate killed/survived counts. `--output PATH` also writes it to a file. Counts are unavailable when the run is incomplete.

## CI composition

Run the project's normal parallel suite and coverage merge before a narrower mutation selection:

    bundle exec polyrun run-shards --workers 2 --merge-coverage -- bundle exec rspec
    bundle exec polyrun mutate --enable --subjects-file subjects.txt --shard 1 --total 3 --workers 2 --output mutation-1.json -- bundle exec rspec

Repeat the mutation job for shard numbers 1 through 3 with the same subject file. Mutation shard numbers are one-based; the existing worker environment uses its own documented index convention. Keep each job's report as an artifact and use the command's status as its gate. Use `graph check PLAN --prove -- bundle exec rspec` to prove a staged edit before apply. These commands stay independently useful; a graph plan is not required for mutation testing.

## Observation and measurement

    polyrun observe --enable --output tmp/observed.json -- ruby -Ilib test/probe.rb
    polyrun measure --enable --label tests --output tmp/measurement.json -- bundle exec rspec
    polyrun measure --enable --ceilings ceilings.json -- ruby -Ilib test/probe.rb

Observe injects an opt-in Ruby TracePoint hook through RUBYOPT. It records bounded call counts, named subjects, and relative paths within the requested root. It skips anonymous owners, records no arguments or receiver values, and disables injection into descendants. Missing or truncated observations are not complete mutation selections. Observation proves calls in that run, not test coverage or static dispatch.

Measure reports wall time, orchestrator CPU, reaped child CPU, an orchestrator resident-memory sample, and command status. Memory is not child peak RSS; CPU is only an energy proxy. Ceilings fail closed for invalid or unavailable metrics. Local pressure commands, isolated process-lifetime RSS measurements, and their limits are documented in [the benchmark binding](../benchmarks/quality-binding.md).

All child commands use argument arrays, bounded output, a finite timeout, and process-group cancellation. Project tests and prove commands execute with the caller's authority. Copies isolate source edits, not filesystem or network access. Reports may contain project paths and command diagnostics; review them before sharing.
