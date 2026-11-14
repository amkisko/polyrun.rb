# Configurable quality tools review

## Participants

Andrei Makarov (@amkisko).

## Decisions

Extend experimental RFC-0010 with explicit activation and configuration. Graph, mutation, observe, and measure default to disabled. YAML or an explicit environment switch enables a feature; --enable and --no-enable are invocation overrides. Shared global defaults do not activate features. Direct library calls remain explicit requests to execute their operation.

Use the existing configuration loader, suite overlays, config inspection, and validation commands. Separate the default registry, type validation, merging, CLI adaptation, and execution. Share workers with existing parallel commands, and share timeouts with existing worker processes. Expose resource budgets, source and staging filters, operator families, selection, commands, outputs, and per-example quality settings without Ruby edits.

Use only Polyrun implementation and Ruby APIs. No third-party graph or mutation source, package, executable, or source checkout was added. No dependency version or lockfile graph changed. This is an implementation and packaging check, not a legal opinion about unrelated existing repository code.

The root-default follow-up in 20261114150543_root-config-defaults.md supersedes the unshipped global section. The results below describe the earlier source state.

## Effects

The first five configuration behavior tests all failed before implementation. They now exercise activation, shared workers, CLI precedence, configured source scope and graph storage, native mutation operators, quality command defaults, validation diagnostics, and suite overlays.

A cached index initially bypassed a newly lowered node ceiling. The added regression first failed; indexing now checks the limit before cache reuse. Mutation source discovery also enforces the configured total node budget.

A configured prove default initially affected index and inspect as well as check. The full configured workflow first failed during index; proof defaults now apply only to graph check. Explicit invalid command combinations still fail.

Source exclusion initially matched directories only. A file-exclusion regression failed before applying the filter to regular source files too. Shared output, source-byte, staging-byte, copy-byte, and worker budgets have executable boundary tests. Key-file exclusion remains an invariant.

Main-file spec-quality activation initially ignored an explicitly selected integration root. A subprocess hook test produced no quality artifact before the fix. RSpec and Minitest activation now resolve settings from the same root as collection. The root-specific RSpec subprocess writes a real per-example report without an activation environment flag.

Graph output initially accepted a report path without writing it. A report-output regression failed before connecting that setting to the emitted result. Irrelevant feature keys were also accepted; typed ownership now rejects source-scan options on the measurement command while shared global settings apply only to relevant features.

The terminal surface is the command family, disabled-feature diagnostic, effective settings JSON, and configuration guide. Checks cover absent settings, explicit activation, explicit disable overrides, malformed types, unknown keys, configured commands, suite overlays, and resource failures. The guide includes a complete YAML example and inspection commands. No graphical surface or remote service is added.

The feature remains a cooperative local workflow. Configuration never disables symlink checks, freshness checks, check receipts, subprocess cleanup, or secret-key exclusions. Reports and settings can contain caller-selected project paths and command diagnostics. No telemetry or device identifier is introduced.

### Resource and pressure outcome

benchmarks/quality-configuration-episode.json owns the raw samples, source digest, calibration, fixed ceilings, package samples, and validation counts for this follow-up. Its earlier configuration replay is retained as intermediate evidence. The earlier native episode remains linked separately.

The final configuration replay calibrated its meters before baseline, raised the fixture load from five to fifty, tightened the observation primary from the measured initial stress envelope to the existing production ceiling, and completed ten source-change trials with three samples per load. Trials 1 through 3 failed the observation limit. Trials 4 through 10 passed. The complete production implementation then passed every series against the same unchanged limits. Failed samples remain in the artifact; no ceiling was raised.

No test suite ran concurrently with the pressure replay. Other host activity and OS file caches remain uncontrolled; no small causal speedup or general capacity claim is made. RSS is process-lifetime, CPU is an energy proxy, and network is not_in_scope. Three final gem builds preserve the same compressed size and zero runtime dependencies; the artifact compares their bytes with the prior native package. Installed storage, stage RSS, and physical energy were not measured.

### Validation

Temporary report and log destinations are represented by TEMP_JSON below. The executable commands and meaningful arguments are retained.

- POLYRUN_COVERAGE=1 bundle exec rspec --format json --out TEMP_JSON: exit 0; 917 examples, zero failures, seven pending, zero errors outside examples.
- bundle exec rspec spec/polyrun/quality spec/polyrun/config spec/polyrun/config_spec.rb spec/polyrun/cli_config_spec.rb spec/polyrun/spec_quality/config_spec.rb spec/polyrun/cli_run_shards_worker_timeouts_spec.rb: exit 0; 123 examples, zero failures.
- bundle exec rspec spec/polyrun/quality/configured_hook_spec.rb spec/polyrun/rspec_support_spec.rb spec/polyrun/minitest_support_spec.rb: exit 0; 17 examples, zero failures.
- bundle exec rspec spec/polyrun/quality/tool_limits_spec.rb spec/polyrun/config/resolver_spec.rb: exit 0; 24 examples, zero failures.
- bundle exec rubocop --cache false --format simple: exit 1; 366 files, nine pre-existing indentation offenses in spec/release_spec.rb and usr/lib/release_version_check.rb. The unrelated release files remain untouched.
- bundle exec rubocop --cache false lib/polyrun/config lib/polyrun/config.rb lib/polyrun/cli/tool_options.rb lib/polyrun/cli/graph_command.rb lib/polyrun/cli/mutation_command.rb lib/polyrun/cli/quality_commands.rb lib/polyrun/cli/helpers.rb lib/polyrun/cli/run_shards_plan_options.rb lib/polyrun/cli/ci_shard_run_command.rb lib/polyrun/cli/help.rb lib/polyrun/cli.rb lib/polyrun/graph lib/polyrun/mutation lib/polyrun/quality lib/polyrun/spec_quality/config.rb lib/polyrun/spec_quality.rb lib/polyrun/rspec_support.rb lib/polyrun/minitest_support.rb spec/polyrun/quality polyrun.gemspec: exit 0; 60 files, no offenses.
- QUALITY_EPISODE_OUTPUT=TEMP_JSON ruby benchmarks/quality_trials.rb: exit 0; ten cycles and a separate successful production gate. The report path was an operator-selected disposable file before retaining its measurement payload.
- ruby benchmarks/quality_smoke.rb: exit 0; graph index, inspect, plan, staged prove, and apply succeeded; four mutations killed, zero survived.
- bundle exec rbs -I sig validate: exit 0.
- git diff --check: exit 0.

The standalone package example builds and extracts a gem, clears bundle and library injection, then runs graph and mutation commands using only the package and Ruby. Runtime gem dependencies remain zero.

## Next

Confirm the operator display name for durable notes. Consuming-project and additional Ruby-runtime evaluation remain open before promoting the experimental contract.

## Source

- ../../rfcs/0010-graph-and-quality-orchestration.md.
- ../QUALITY_CONFIGURATION.md.
- ../QUALITY.md.
- ../issues/20261114090000_graph-and-mutation-adoption.md.
- ../../spec/polyrun/quality/configuration_spec.rb.
- ../../spec/polyrun/quality/tool_limits_spec.rb.
- ../../spec/polyrun/quality/configured_hook_spec.rb.
- ../../benchmarks/quality-configuration-episode.json.
- ../../benchmarks/quality-binding.md.
