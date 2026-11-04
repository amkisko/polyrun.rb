# Host config diff engineering audit

## Decisions

Review the working-tree diff, including new Ruby files and specs, against HEAD. Accept only findings reproduced by failing executable specs. Apply each fix after replication and verify it before the next iteration. Severity describes the demonstrated result; unreplicated suspicions are excluded.

## Effects

Seven confirmed findings were fixed: three medium and four low. All have high confidence and observed evidence. No critical or high impact was demonstrated.

### F01: Selected suite coverage ignored

- Severity: medium. Category: contract. Stage: config -> coverage.
- Location: `Coverage::ConfigResolve.load_inline_coverage`.
- Evidence: `bundle exec rspec spec/polyrun/coverage/config_resolve_spec.rb` failed one of four examples. The selected suite specified 90 percent but the resolver returned the root value, 10 percent.
- Impact: the coverage collector and merged gate received a different policy from the selected suite.
- Smallest fix applied: merge the selected suite before reading inline coverage.
- Guard: selected-suite coverage example in `spec/polyrun/coverage/config_resolve_spec.rb`.

### F02: Explicit config lost at downstream coverage consumers

- Severity: medium. Category: contract. Stage: CLI -> worker -> coverage gate.
- Location: `CLI.run`, `CoverageCommands.merge_coverage_after_shards_strict_gate`, `Helpers.coverage_minimum_line_gate_from_polyrun_coverage_yml`.
- Evidence: `bundle exec rspec spec/polyrun/cli_coverage_config_spec.rb` first reproduced a merged gate returning exit 0 for 50 percent coverage despite a selected 99 percent minimum. Worker probes then returned the root minimum, 10, instead of the selected 90 in both `run-shards` and `ci-shard-run`.
- Impact: the explicit file's coverage policy did not reach workers or the parent gate.
- Smallest fix applied: scope an absolute `POLYRUN_CONFIG` to the CLI invocation so all child paths inherit it, restore the caller's value afterward, and pass the explicit path into the merged gate.
- Guard: three integration examples in `spec/polyrun/cli_coverage_config_spec.rb`.

### F03: Suite selection persisted into later CLI calls

- Severity: medium. Category: state isolation. Stage: CLI -> config.
- Location: `CLI.run`.
- Evidence: `bundle exec rspec spec/polyrun/cli_suite_spec.rb` failed the same-process invocation example. A later call without `--suite` returned two workers instead of the root value, five.
- Impact: a completed invocation changed the configuration of the next invocation.
- Smallest fix applied: restore `POLYRUN_SUITE` in `ensure`, including error returns.
- Guard: same-process CLI example in `spec/polyrun/cli_suite_spec.rb`.

### F04: Validation accepted a non-mapping root

- Severity: low. Category: validation. Stage: YAML -> config -> validate.
- Location: `Config.load` before `Suite.merge`.
- Evidence: `bundle exec rspec spec/polyrun/cli_validate_spec.rb` failed one of three examples. A YAML array was converted to an empty mapping and `validate` reported success.
- Impact: invalid config passed the new validation command.
- Smallest fix applied: reject a non-mapping root before applying suites; preserve empty-file defaults.
- Guard: non-mapping root example in `spec/polyrun/cli_validate_spec.rb`.

### F05: Missing suite names fell through to the default command

- Severity: low. Category: CLI contract. Stage: argv -> dispatch.
- Location: `CLI.parse_global_cli!`.
- Evidence: `bundle exec rspec spec/polyrun/cli_suite_spec.rb` failed both missing-name examples. `--suite` and `--suite=` reported that no tests existed instead of rejecting the missing name.
- Impact: argument errors entered default dispatch. The fixture did not demonstrate preparation or worker side effects, so severity is limited to the observed routing and diagnostic defect.
- Smallest fix applied: reject missing or blank names before dispatch.
- Guard: both missing-name examples in `spec/polyrun/cli_suite_spec.rb`.

### F06: Doctor reported the wrong coverage source

- Severity: low. Category: diagnostic lineage. Stage: config -> CLI output.
- Location: `DoctorCommand.doctor_lines`, `Coverage::ConfigResolve.load`.
- Evidence: `bundle exec rspec spec/polyrun/cli_doctor_spec.rb` failed one of four examples. `--config selected.yml doctor` printed `coverage.source: none` despite coverage in the selected file.
- Impact: the diagnostic command misidentified the active policy source.
- Smallest fix applied: resolve coverage using the loaded config path and label the actual selected file. A winning dedicated coverage file is resolved without loading discarded inline settings.
- Guard: explicit-source example in `spec/polyrun/cli_doctor_spec.rb`.

### F07: Doctor exceeded the start worker limit

- Severity: low. Category: resource bound and diagnostic lineage. Stage: config -> CLI output.
- Location: `DoctorCommand.doctor_lines`.
- Evidence: `bundle exec rspec spec/polyrun/cli_doctor_spec.rb` failed one of five examples. YAML workers 12 produced 12 workers and shard names through 11 although `start` caps its workers at 10.
- Impact: the summary named two databases beyond the start limit. Larger resource exhaustion was not claimed.
- Smallest fix applied: cap the summary using the existing worker limit before enumerating shard names.
- Guard: bounded worker summary example in `spec/polyrun/cli_doctor_spec.rb`.

### Verification

- `bundle exec rspec --format json --out tmp/engineering-audit-rspec.json`: exit 0; 786 examples, zero failures, seven pending, zero errors outside examples.
- `POLYRUN_COVERAGE=1 bundle exec rspec spec/polyrun/cli_coverage_config_spec.rb spec/polyrun/cli_suite_spec.rb spec/polyrun/cli_validate_spec.rb spec/polyrun/cli_doctor_spec.rb spec/polyrun/config_spec.rb spec/polyrun/config spec/polyrun/coverage/config_resolve_spec.rb spec/polyrun/coverage/rails_spec.rb --format json --out tmp/engineering-audit-coverage-specs.json`: 59 examples, zero failures. Process exit 1 came from measuring a subset against the whole-project 90 percent gate; measured coverage was 40.93 percent (3306/8077 lines).
- `POLYRUN_COVERAGE=1 bundle exec rspec --format json --out tmp/engineering-audit-full-coverage.json`: exit 0; 786 examples, zero failures, seven pending, zero errors outside examples. The fresh `coverage/polyrun-fragment-0.json` contained 7502 covered lines out of 8182 across 150 files (91.69 percent), above the configured 90 percent minimum. The prior merged report was stale and was not used.
- `bundle exec ruby -rpolyrun -rjson -e 'puts JSON.generate(Polyrun::Coverage::Merge.console_summary(Polyrun::Coverage::Merge.merge_files(["coverage/polyrun-fragment-0.json"])))'`: exit 0; confirmed the fresh fragment counts and 91.68907357614275 percent coverage.
- `bundle exec rubocop --cache false --format simple`: exit 0; 310 files inspected, no offenses. The initial cached run could not write outside the workspace. Eight existing diff offenses were autocorrected; the second top-level config group was moved to `config_spec.rb` without duplicating examples.
- `bundle exec rbs -I sig validate`: exit 0, no diagnostics.
- `git diff --check`: exit 0, no diagnostics.

### Resource, trace, and surface assessment

Runtime: Ruby 4.0.2 on arm64 Darwin. The existing 2000-iteration config benchmark passed its less-than-five-second budget for each operation: Effective.build 0.0274s, file coverage resolution 0.0785s, inline resolution 0.1591s, suite merge 0.0128s. Command: `/usr/bin/time -l env POLYRUN_BENCH=1 bundle exec rspec spec/performance/benchmark_config_resolve_spec.rb --tag benchmark`. RSpec passed one example; the wrapper exited 1 because the sandbox denied its clock-rate query. It reported 0.44 user and 0.18 system CPU seconds, used here as an energy proxy. RSS and joules were not measured; no reduction claim is made.

Trace review followed config paths, selected suite names, synthetic database names, stdout/stderr, child environments, and local coverage files. The changed diagnostics print explicitly requested local configuration. This review demonstrated no new tracking identifier or network telemetry and did not inspect retention outside the changed paths.

The person-facing surface is the CLI: config values, validate diagnostics, doctor summaries, and missing-argument errors. Captured runs cover normal, empty/no-config, and error results. Labels and exit status let the caller distinguish success from refusal. The doctor database summary is bounded to ten names. Physical narrow-terminal wrapping, screen-reader behavior, and generated task execution in a real Rails application were not assessed. These are coverage limits, not findings.

Contract, lineage, performance, resource/budget, trace/identification, terminal presentation, local input/child-process boundaries, and generated-source checks apply. Boundary/control review covers CLI commands and child-process feedback; there is no physical plant. HTTP identity, browser/native bridges, cloud deployment, message protocols, multi-principal data isolation, personal-data collection, and learned-systems modes have no changed surface. No dependency graph change or advisory signal was encountered; no dependency audit was opened.

## Next

Ruby 3.4 and Linux remain CI checks; this session used Ruby 4.0.2 on macOS. No reproduced finding remains unfixed.

## Source

- `docs/issues/20261104153500_host-config-contract-gaps.md`
- `docs/changelogs/20261104154200_host-config-contract-fixes.md`
- `spec/polyrun/cli_coverage_config_spec.rb`
- `spec/polyrun/cli_suite_spec.rb`
- `spec/polyrun/cli_validate_spec.rb`
- `spec/polyrun/cli_doctor_spec.rb`
- `spec/polyrun/coverage/config_resolve_spec.rb`
- `spec/performance/benchmark_config_resolve_spec.rb`
