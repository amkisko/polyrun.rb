# Root configuration defaults

## Participants

Andrei Makarov (@amkisko).

## Decisions

Keep shared defaults at the YAML root and feature-specific overrides in their existing sections. Remove the unshipped global section instead of retaining an alias or a second worker setting. Reject global at the root and in a selected suite before executing a feature. Activation remains feature-specific.

Preserve the existing numeric-string worker input at its single root location. Apply root settings through the same typed default registry, suite merge, environment overrides, and CLI overrides. Existing workers read root timeout directly; per-example quality reads root source_roots directly. No dependency changes are involved.

## Effects

The before run of the migrated configuration cases and new root-default cases produced 23 examples and nine failures. The focused after run passed 23 examples. The broader configuration, quality, and worker-timeout run passed 128 examples with zero failures.

Tests cover validation and effective settings, inactive features with shared defaults present, root-to-suite-to-feature precedence, recursive staging-budget merging, environment and CLI overrides, per-example source scope, ordinary worker timeout, and refusal of the removed section without creating graph state.

The command-line configuration guide and the experimental RFC now use a single shared level. The guide presents ordinary YAML root settings and inspection commands. The command help calls its CLI flag group global options, which does not name a YAML section. This terminal and documentation assessment covers the settings hierarchy and actionable error states; no graphical screen is added.

The earlier pressure episodes remain evidence for their recorded source digests. This simplification makes no optimization or scaling claim. A calibrated three-sample regression gate against the unchanged local ceilings checks resource effects; it is not a new optimization episode.

### Validation

Temporary JSON and log destinations and the isolated toolchain paths are represented by TEMP_JSON below. Both test copies contain the current library and spec source.

- BUNDLE_GEMFILE=gemfiles/ruby34.gemfile POLYRUN_COVERAGE=1 bundle exec rspec --format json --out TEMP_JSON: exit 0 on Ruby 3.4.11; 922 examples, zero failures, seven pending, zero errors outside examples.
- BUNDLE_GEMFILE=gemfiles/ruby40.gemfile POLYRUN_COVERAGE=1 bundle exec rspec --format json --out TEMP_JSON: exit 0 on Ruby 4.0.2; 922 examples, zero failures, seven pending, zero errors outside examples.
- bundle exec rspec spec/polyrun/config spec/polyrun/config_spec.rb spec/polyrun/cli_config_spec.rb spec/polyrun/quality spec/polyrun/spec_quality/config_spec.rb spec/polyrun/cli_run_shards_worker_timeouts_spec.rb: exit 0; 128 examples, zero failures.
- bundle exec rubocop --cache false --format simple: exit 0; 367 files, no offenses.
- bundle exec rbs -I sig validate: exit 0.
- bundle exec polyrun build-paths: exit 0; 165 spec paths.
- ruby benchmarks/quality.rb self-test: calibration passed.
- LOAD=50 SAMPLES=3 ruby benchmarks/quality.rb gate benchmarks/quality-ceilings.json: exit 0; three samples, no failed series, no ceiling changes. Raw values and source digest are retained in benchmarks/quality-root-defaults-gate.json.
- ruby benchmarks/quality_smoke.rb: exit 0; the graph edit workflow passed, four mutations killed, zero survived.
- git diff --check: exit 0.

Rebuild and verify the local 3.1.0 gem and regenerate its publication notes from the updated changelog. The candidate remains 198144 compressed bytes with zero runtime gem dependencies. No tag or publication is performed.

## Next

Confirm the operator display name for durable notes.

## Source

- ../QUALITY_CONFIGURATION.md.
- ../../rfcs/0010-graph-and-quality-orchestration.md.
- ../../spec/polyrun/config/root_defaults_spec.rb.
- ../../spec/polyrun/quality/configuration_spec.rb.
- ../../benchmarks/quality-binding.md.
- ../../benchmarks/quality-root-defaults-gate.json.
- ../changelogs/20261114144753_release-3-1-0.md.
