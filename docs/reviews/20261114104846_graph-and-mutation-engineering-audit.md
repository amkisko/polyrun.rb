# Native graph and mutation engineering audit

## Participants

Andrei Makarov (@amkisko).

## Decisions

Scope is experimental RFC-0010: graph ingress, source indexing, staged edits, check receipts, journaled apply, native mutation generation and execution, observations, measurements, packaging, and affected test isolation. Keep all implementation in Polyrun with Ruby standard libraries and no new package dependency.

Run resource/budget, trace/identification, local filesystem and subprocess security, contract, performance, observability, and terminal-surface review. Child commands and filesystem writes define the boundary. No physical plant, browser, HTTP identity, hosted service, or learned model is added, so their specialized modes do not apply. This review is feature-scoped and does not certify the entire repository.

The configuration follow-up in 20261114141417_configurable-quality-tools.md supersedes the earlier unshipped activation and fixed-budget behavior. Numerical evidence here belongs to the earlier source digest.

## Effects

### Graph and recovery findings

Medium severity, high confidence: checking originals one file at a time during writes can leave earlier files changed when a later write fails. Check all source hashes and the complete source inventory before apply. Bind staged bytes and metadata to a successful receipt. Native apply now uses backups, per-file replacement, and a recovery journal. An injected later ENOSPC restores earlier writes; an interrupted-journal fixture restores its original. Recovery stops on unrelated source changes. Whole-tree atomicity and power-loss durability are not claimed.

Medium severity, high confidence: missing staged originals could receive a receipt. A regression test preceded staged-file existence validation. Symbolic links, escaping paths, stale originals, added source files, changed metadata, duplicate call edits, and ambiguous selectors fail closed. Indexing never evaluates project code. Dynamic graph edges stay unknown rather than being presented as certain dispatch.

Medium severity, high confidence: a successful prove command could alter source after syntax checking and have those altered bytes approved. The added public client regression failed with four examples and one failure before the fix. Create the candidate receipt before proof and verify it afterward under the workspace lock. Any proof failure or staged drift invalidates approval. The focused client and standalone-package check then passed five examples.

### Mutation and subprocess findings

The native engine generates bounded syntax-valid byte edits without retaining a full source copy per mutation. It deduplicates edits, refuses missing or ambiguous subjects, runs a clean baseline, and gives every case a separate project copy. A copy-byte ceiling bounds repeated staging. Extensible operator objects own mutation rules; the runner owns scheduling and result integrity.

Medium severity, high confidence: per-process output limits alone permit aggregate diagnostics to grow with case count. A synchronized report budget now fails incomplete with unavailable counts when exhausted. Failed baselines, timed-out mutations, excessive output, missing commands, signals, and non-test exit statuses never count as kills. Exit 1 is the consuming test command's failure contract; unrelated setup failures using that same status remain indistinguishable.

Medium severity, high confidence: binary subprocess output could prevent JSON serialization. Normalize captured diagnostics to UTF-8. Low severity, high confidence: second-pipe allocation failure leaked the first descriptors; incremental allocation inside the cleanup scope now passes the injected EMFILE regression. Argv execution, closed stdin, process-group cancellation, descendant-held pipes, timeout, and output overflow have behavioral coverage.

Existing RSpec hook tests contaminated the global test process. One real subprocess integration replaces duplicate hook installation and isolates inherited coverage settings. No production design was changed merely to expose private methods to tests.

### Resources, trace, and terminal surface

The producing measurement artifact is benchmarks/quality-episode.json. It owns calibration, raw samples, trial decisions, package sizes, and acceptance. benchmarks/quality-ceilings.json owns the native workload's fixed limits. Benchmark commands and their scope are defined in benchmarks/quality-binding.md. Earlier prototype workloads are not comparable performance baselines.

Observation emits bounded relative source paths, named subjects, call counts, and truncation state to a caller-selected local file. It records no arguments, receiver values, anonymous identities, or device identifiers. Tests cover root filtering, descendant injection, fork behavior, truncation, and preserving prior output when no replacement trace exists. No remote destination is introduced. Trusted commands can still print arbitrary diagnostics and paths; sharing remains under caller control.

The person-facing surface is the terminal command family, help, and JSON reports. CLI checks cover successful edits, missing and ambiguous inputs, survivors, incomplete runs, empty shards, failed proof, stale approval, and command limits. Commands are keyboard-operated; JSON has no viewport dependency. Large diagnostic records still need human review in the consuming terminal. No graphical surface was added.

### Pressure outcome and limits

The final replay calibrated before baseline, stepped from five to fifty fixture units, tightened the observation primary from its measured initial stress envelope, and completed ten temporary source-change trials with three samples per load. Trials 1 through 3 failed the observation ceiling; those failures remain in the raw artifact. Trials 4 through 10 passed all series. Production received a separate successful gate against the same fixed limits. A previous exploratory ten-cycle replay is retained separately, without treating it as evidence of the later explicit ratchet.

The accepted ceilings were proposed from actual native indexing, native mutation execution, and observation. No test suite ran concurrently with either replay. There was no explicit warmup; OS caches and other host activity were uncontrolled. The episode establishes a local fixture result, not a causal small timing gain, a production capacity bound, or near-linear scaling for every stage. RSS is process-lifetime rather than stage RSS or summed concurrent memory. CPU is a proxy, not measured energy. Network is not_in_scope.

Three gem builds each measured the same compressed size with zero runtime dependencies. The artifact preserves prior prototype package samples and final samples; the earlier source state is not reconstructed here. Compressed package bytes are not installed storage or resident memory. No dependency graph or runtime pin changed, so a dependency-upgrade resource comparison is outside this work.

### Final validation

Temporary JSON and log destinations are omitted below; the executable commands and relevant arguments are retained. Measurements and counts are frozen in benchmarks/quality-episode.json.

- POLYRUN_COVERAGE=1 bundle exec rspec --format json --out TEMP_JSON: exit 0; 897 examples, zero failures, seven pending, zero errors outside examples.
- bundle exec rspec spec/polyrun/quality: exit 0; 57 examples, zero failures.
- bundle exec rubocop --cache false lib/polyrun/graph lib/polyrun/mutation lib/polyrun/quality lib/polyrun/cli/graph_command.rb lib/polyrun/cli/mutation_command.rb lib/polyrun/cli/quality_commands.rb lib/polyrun/cli.rb lib/polyrun/cli/help.rb spec/polyrun/quality spec/polyrun/rspec_support_spec.rb spec/polyrun/spec_quality/rspec_hook_spec.rb polyrun.gemspec --format simple: exit 0; 40 files, no offenses.
- bundle exec rubocop --cache false --format simple: exit 1; 357 files, nine pre-existing indentation offenses in spec/release_spec.rb and usr/lib/release_version_check.rb. Those files were already modified at task start and were left untouched.
- bundle exec rbs -I sig validate: exit 0.
- git diff --check: exit 0.
- ruby benchmarks/quality_smoke.rb: exit 0; full graph edit workflow passed, four mutations killed and zero survived.
- ruby benchmarks/quality.rb self-test: pass, including distinct p95 series and direct meter checks.
- LOAD=5 SAMPLES=3 ruby benchmarks/quality.rb measure: exit 0, native baseline recorded.
- LOAD=50 SAMPLES=3 ruby benchmarks/quality.rb propose: exit 0, explicit native ceiling proposal recorded.
- QUALITY_EPISODE_OUTPUT=TEMP_JSON ruby benchmarks/quality_trials.rb: exit 0, ten cycles and separate production gate accepted. The operator selected a disposable output file before retaining the measurement payload.

The package spec builds and extracts the gem, clears library and bundle injection, then indexes, plans, checks, applies, executes the changed code, and mutation-tests using only packaged files and Ruby. No source checkout or separately installed graph or mutation executable is involved.

## Next

Evaluate real consuming projects and additional Ruby runtimes before promoting experimental interfaces. Confirm the operator display name for durable notes.

## Source

- ../../rfcs/0010-graph-and-quality-orchestration.md.
- ../issues/20261114090000_graph-and-mutation-adoption.md.
- ../QUALITY.md.
- ../../benchmarks/quality-binding.md.
- ../../benchmarks/quality-episode.json.
- ../../spec/polyrun/quality/.
