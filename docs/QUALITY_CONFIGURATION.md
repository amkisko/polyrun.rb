# Quality tool configuration

Graph, mutation, observation, and measurement are disabled by default. Enable a feature in `polyrun.yml`, or pass `--enable` for one invocation. `--no-enable` disables it for that invocation even when configuration or the environment enables it. Shared defaults never enable features. Existing test workers do not run these tools automatically.

All graph and mutation implementation ships in the Polyrun gem. No other graph or mutation package, executable, database, or source checkout is needed. Test commands still use the consuming project's ordinary dependencies.

## Root defaults and feature settings

```yaml
workers: 2
timeout: 120
command: [bundle, exec, rspec]
max_output_bytes: 1048576
source_roots: [lib, app]
max_source_files: 100000
max_source_file_bytes: 10485760
max_source_bytes: 67108864
staging:
  max_files: 10000
  max_bytes: 67108864
  exclude: [vendor, node_modules, tmp, log, coverage, pkg, benchmarks]
  exclude_paths: []
  include_hidden: [.rspec, .ruby-version]
graph:
  enabled: true
  state_dir: .polyrun/graph
  timeout: 60
  max_nodes: 250000
  max_operations: 1000
  max_diff_bytes: 524288
  max_plan_bytes: 1048576
  max_receipt_files: 100000
mutation:
  enabled: true
  subjects: ['Account#save']
  operators: [literal, operator, body]
  max_workers: 32
  max_mutations: 1000
  max_subjects: 10000
  max_report_bytes: 16777216
  max_copy_bytes: 1073741824
quality:
  observe:
    enabled: true
    output: tmp/observed.json
    max_entries: 10000
    max_artifact_bytes: 16777216
    command: [ruby, -Ilib, test/probe.rb]
  measure:
    enabled: true
    label: tests
    output: tmp/measurement.json
    ceilings: {wall_s: 120}
  spec_quality:
    enabled: false
    min_line_churn: 50
    min_query_count: 20
    sample: 1.0
    strict: false
    profile: [cpu, mem]
```

Create parent directories for configured outputs before running commands. Arrays of command arguments execute directly; no shell splitting or interpolation is applied. A command after `--` replaces the configured command. CLI subjects or observed files replace their configured lists; repeated CLI selections accumulate within that invocation. Other arrays replace inherited arrays; mappings merge recursively.

The precedence is CLI, environment, feature settings, shared root settings, defaults. Each shared setting has one root location. The `global` section is rejected, including inside selected suites. Selected `suites` overlays merge before resolution; `--config`, `POLYRUN_CONFIG`, and `--suite` work with all tool commands. `POLYRUN_WORKERS` overrides worker defaults for mutations and existing parallel workers. Root `timeout` also supplies existing worker timeouts; their specific `--worker-timeout` and `POLYRUN_WORKER_TIMEOUT_SEC` remain overrides. Root-level `root` and `command` defaults apply to the new tool commands; existing workers retain their working-directory and command conventions.

`POLYRUN_GRAPH`, `POLYRUN_MUTATION`, and `POLYRUN_QUALITY` enable their corresponding commands with `1`, `true`, `yes`, or `on`; `0`, `false`, `no`, or `off` disable them. `POLYRUN_TIMEOUT` and `POLYRUN_MAX_OUTPUT_BYTES` supply shared environment overrides. Invalid values fail instead of silently selecting another setting.

A command's `--root` selects automatic project configuration discovery. Relative root settings are resolved against that discovery directory or the invoking directory. Output and subject-file paths resolve against the effective root. Source roots and graph state directories must stay inside the project. Changing source scope can invalidate an existing plan; selecting another state directory selects another local index and plan collection.

## Complete settings and validation

Inspect every supported key and effective default without enabling the tool:

    polyrun config graph
    polyrun config mutation
    polyrun config quality.observe
    polyrun config quality.measure
    polyrun config workers
    polyrun validate
    polyrun --suite review config mutation

Root shared settings include `root`, `workers`, `timeout`, `command`, `output`, `max_output_bytes`, `max_input_bytes`, `max_artifact_bytes`, `source_roots`, `source_fallback`, `source_exclude`, `max_nodes`, `max_source_files`, `max_source_file_bytes`, `max_source_bytes`, and `staging`. Activation stays in feature blocks; root defaults never enable a feature. A feature accepts only keys it uses: source and staging settings apply to graph and mutation; workers apply to mutation. `quality` shares execution defaults for observe and measure before their own overrides. Irrelevant feature keys are errors, while shared root defaults are applied only where relevant.

Graph writes `output` in the selected CLI format. Graph also accepts `json`, `calls`, `callers`, `callees`, `control_plane`, and `prove`, in addition to the limits shown above. Configure `prove: true` and a command to run behavioral checks without repeating the command after `--`. `--no-prove` runs syntax checks only. Graph JSON and inspection flags have corresponding `--no-` overrides.

Mutation also accepts `subjects_file`, `observed`, `plan`, `shard`, `total`, and `output`. Mutation limits and worker ceilings are positive configurable values; increasing them is an explicit resource-budget decision. Shard numbering remains one-based. Operators select the built-in rule families; Ruby callers may provide additional operator objects through the runner API.

Unknown keys, malformed types, escaping source/state paths, and nonpositive resource bounds fail validation before execution. Output truncation, process cleanup, source freshness, symlink rejection, receipt integrity, and key-file exclusions remain invariants. Limits do not turn copied test execution into an OS sandbox.

## Existing per-example quality collection

`quality.spec_quality` accepts the settings documented in [SPEC_QUALITY.md](SPEC_QUALITY.md), including collection filters, thresholds, profiling, sampling, and report gates. Root `source_roots` supplies its `track_under` fallback. The existing environment activation and disable switches still apply; `POLYRUN_SPEC_QUALITY_DISABLE` always prevents collection. `POLYRUN_QUALITY` controls the observe and measure commands, not per-example collection.

The default dedicated spec-quality file provides settings below the main file's `quality.spec_quality` block. An explicitly selected dedicated file overrides the main block, followed by environment and explicit Ruby API overrides. Enabling settings does not install test hooks: use the existing RSpec, Minitest, or Quick integration. Direct graph and mutation Ruby API calls are explicit opt-in; pass a resolved `Polyrun::Config::Tools.resolve` mapping as `settings:` to use the same defaults and validation.
