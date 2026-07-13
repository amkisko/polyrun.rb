module Polyrun
  class CLI
    module Help
      def print_help
        Polyrun::Log.puts <<~HELP
          usage: polyrun [global options] [<command> | <paths...>]

          With no command, runs parallel tests for the detected suite: RSpec under spec/, Minitest under test/, or Polyrun Quick (same discovery as polyrun quick). If the first argument is a known subcommand name, it is dispatched. Otherwise, path-like tokens (optionally with run-shards flags such as --workers) shard those files in parallel; see commands below.

          global:
            -c, --config PATH    polyrun.yml path (or POLYRUN_CONFIG)
            -v, --verbose
            -h, --help

          Trace timing (stderr): DEBUG=1 or POLYRUN_DEBUG=1
          Coverage: POLYRUN_COVERAGE=1 (or config/polyrun_coverage.yml + POLYRUN_QUICK_COVERAGE=1); POLYRUN_COVERAGE_DISABLE=1 skips; POLYRUN_COVERAGE_BRANCHES=1 for branch data in fragments; POLYRUN_COVERAGE_VERBOSE=1 for per-worker and merged console summaries
          Benchmark profiles (stdout): POLYRUN_BENCH=1 (files still written under tmp/benchmarks/)
          Hooks shell output: POLYRUN_HOOKS_VERBOSE=1 or -v / POLYRUN_VERBOSE=1 (or DEBUG); failures always print
          Merge profiling (stderr): POLYRUN_PROFILE_MERGE=1 (or verbose / DEBUG)
          Post-merge formats (run-shards): POLYRUN_MERGE_FORMATS (default: json,lcov,cobertura,console,html)
          Start skips: POLYRUN_SKIP_BUILD_SPEC_PATHS=1, POLYRUN_START_SKIP_PREPARE=1, POLYRUN_START_SKIP_DATABASES=1
          Paths build skip: POLYRUN_SKIP_PATHS_BUILD=1
          Slow merge warning (seconds, default 10; 0 disables): POLYRUN_MERGE_SLOW_WARN_SECONDS
          Failure merge: run-shards --merge-failures (enable failure fragments in test setup); POLYRUN_MERGE_FAILURES=1, POLYRUN_FAILURE_FRAGMENT_DIR, POLYRUN_MERGED_FAILURES_OUT
          Parallel workers: POLYRUN_WORKERS default 5, max 10 (run-shards / parallel-rspec / start). CI local processes per job: POLYRUN_SHARD_PROCESSES or ci-shard --shard-processes (not POLYRUN_WORKERS)
          Per-worker wall timeout: --worker-timeout SEC or POLYRUN_WORKER_TIMEOUT_SEC. Exit 124; parent stops remaining workers.
          Per-worker idle timeout: --worker-idle-timeout SEC or POLYRUN_WORKER_IDLE_TIMEOUT_SEC after a progress ping (POLYRUN_WORKER_PING_FILE). Enable pings in test setup. Exit 125. Optional periodic pings: POLYRUN_WORKER_PING_THREAD=1 (POLYRUN_WORKER_PING_INTERVAL_SEC).
          Worker output routing (opt-in): POLYRUN_WORKER_OUTPUT_ROUTING=1 or POLYRUN_WORKER_LOG_DIR; per-shard logs under tmp/polyrun/workers (POLYRUN_WORKER_OUTPUT_PREFIX=0 for log-only)
          Example debug (RSpec, opt-in): POLYRUN_EXAMPLE_DEBUG=1; POLYRUN_DEBUG_SQL / POLYRUN_DEBUG_TRACE
          Sharded formatter compat: silences per-worker seed, summary, and pending lines under POLYRUN_SHARD_* (see docs/SETUP_PROFILE.md)
          Orchestration warnings on process stderr: POLYRUN_ORCHESTRATION_STDERR=1
          Spec quality (opt-in): POLYRUN_SPEC_QUALITY=1; run-shards --merge-spec-quality; merge-spec-quality / report-spec-quality
          Partition timing granularity (default file): POLYRUN_TIMING_GRANULARITY=file|example (experimental; see partition.timing_granularity)
          Partition strategies: round_robin (default, sorted), preserve_order_round_robin (paths-file order), lazy_robin (sorted RR + timing diagnostics), cost_binpack (LPT), hrw. partition.timing_file without strategy implies cost_binpack.

          commands:
            version              print version
            plan                 emit partition manifest JSON
            prepare              run prepare recipe: default | assets (optional prepare.command overrides bin/rails assets:precompile) | shell (prepare.command required)
            merge-coverage       merge SimpleCov JSON fragments (json/lcov/cobertura/console)
            merge-failures       merge per-shard failure JSONL fragments or RSpec JSON files (jsonl/json)
            run-shards           fan out N parallel OS processes (POLYRUN_SHARD_*; not Ruby threads); optional --merge-coverage / --merge-failures / --merge-spec-quality
            parallel-rspec       run-shards + merge-coverage (defaults to: bundle exec rspec after --)
            start                parallel-rspec; auto-runs prepare (shell/assets) and db:setup-* when polyrun.yml configures them; legacy script/build_spec_paths.rb if paths_build absent
            ci-shard-run         CI matrix: build-paths + plan for POLYRUN_SHARD_INDEX / POLYRUN_SHARD_TOTAL (or config), then run your command with that shard's paths after --; optional --shard-processes M or --workers M (POLYRUN_SHARD_PROCESSES; not POLYRUN_WORKERS) for N×M jobs × processes on this host
            ci-shard-rspec       same as ci-shard-run -- bundle exec rspec; optional --shard-processes / --workers / -- [rspec-only flags]
            build-paths          write partition.paths_file from partition.paths_build (same as auto step before plan/run-shards)
            init                 write a starter polyrun.yml or POLYRUN.md from built-in templates (see docs/SETUP_PROFILE.md)
            queue                file-backed batch queue: init (optional --shard/--total etc. as plan, then claim/ack/reclaim/status --json)
            run-queue            init queue and run N workers that claim batches until drained
            quick                quick test runner (describe/it, before/after, let, expect…to, assert_*; optional capybara!)
            hook run <phase>     run one shell hook from polyrun.yml hooks: (e.g. before_suite); optional --shard/--total
            report-coverage      write all coverage formats from one JSON file
            report-junit         RSpec JSON or Polyrun testcase JSON → JUnit XML (CI)
            report-timing        print slow-file summary from merged timing JSON
            merge-timing         merge polyrun_timing_*.json shards
            merge-spec-quality   merge polyrun-spec-quality-fragment-*.jsonl shards
            report-spec-quality  spec quality report from merged JSON (zero-hit, hot lines, churn)
            config               print effective config by dotted path (loaded YAML plus merged prepare.env, resolved partition shard fields, workers)
            env                  print shard + database env (see polyrun.yml databases)
            db:setup-template    migrate template DB (PostgreSQL)
            db:setup-shard       CREATE DATABASE shard FROM template (one POLYRUN_SHARD_INDEX)
            db:clone-shards      migrate templates + DROP/CREATE all shard DBs (replaces clone_shard shell scripts)
        HELP
      end
    end
  end
end
