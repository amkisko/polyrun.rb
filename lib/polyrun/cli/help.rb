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
          Branch coverage in JSON fragments: POLYRUN_COVERAGE_BRANCHES=1 (stdlib Coverage; merge-coverage merges branches)
          polyrun quick coverage: POLYRUN_COVERAGE=1 or (config/polyrun_coverage.yml + POLYRUN_QUICK_COVERAGE=1); POLYRUN_COVERAGE_DISABLE=1 skips
          Merge wall time (stderr): POLYRUN_PROFILE_MERGE=1 (or verbose / DEBUG)
          Post-merge formats (run-shards): POLYRUN_MERGE_FORMATS (default: json,lcov,cobertura,console,html)
          Skip optional script/build_spec_paths.rb before start: POLYRUN_SKIP_BUILD_SPEC_PATHS=1
          Skip start auto-prepare / auto DB provision: POLYRUN_START_SKIP_PREPARE=1, POLYRUN_START_SKIP_DATABASES=1
          Skip writing paths_file from partition.paths_build: POLYRUN_SKIP_PATHS_BUILD=1
          Warn if merge-coverage wall time exceeds N seconds (default 10): POLYRUN_MERGE_SLOW_WARN_SECONDS (0 disables)
          Parallel RSpec workers: POLYRUN_WORKERS default 5, max 10 (run-shards / parallel-rspec / start); distinct from POLYRUN_SHARD_PROCESSES / ci-shard --shard-processes (local processes per CI matrix job)
          Partition timing granularity (default file): POLYRUN_TIMING_GRANULARITY=file|example (experimental per-example; see partition.timing_granularity)

          commands:
            version              print version
            plan                 emit partition manifest JSON
            prepare              run prepare recipe: default | assets (optional prepare.command overrides bin/rails assets:precompile) | shell (prepare.command required)
            merge-coverage       merge SimpleCov JSON fragments (json/lcov/cobertura/console)
            run-shards           fan out N parallel OS processes (POLYRUN_SHARD_*; not Ruby threads); optional --merge-coverage
            parallel-rspec       run-shards + merge-coverage (defaults to: bundle exec rspec after --)
            start                parallel-rspec; auto-runs prepare (shell/assets) and db:setup-* when polyrun.yml configures them; legacy script/build_spec_paths.rb if paths_build absent
            ci-shard-run         CI matrix: build-paths + plan for POLYRUN_SHARD_INDEX / POLYRUN_SHARD_TOTAL (or config), then run your command with that shard's paths after --; optional --shard-processes M or --workers M (POLYRUN_SHARD_PROCESSES; not POLYRUN_WORKERS) for N×M jobs × processes on this host
            ci-shard-rspec       same as ci-shard-run -- bundle exec rspec; optional --shard-processes / --workers / -- [rspec-only flags]
            build-paths          write partition.paths_file from partition.paths_build (same as auto step before plan/run-shards)
            init                 write a starter polyrun.yml or POLYRUN.md from built-in templates (see docs/SETUP_PROFILE.md)
            queue                file-backed batch queue: init (optional --shard/--total etc. as plan, then claim/ack); M workers share one dir; no duplicate paths across claims
            quick                run Polyrun::Quick (describe/it, before/after, let, expect…to, assert_*; optional capybara!)
            hook run <phase>     run one shell hook from polyrun.yml hooks: (e.g. before_suite); optional --shard/--total
            report-coverage      write all coverage formats from one JSON file
            report-junit         RSpec JSON or Polyrun testcase JSON → JUnit XML (CI)
            report-timing        print slow-file summary from merged timing JSON
            merge-timing         merge polyrun_timing_*.json shards
            config               print effective config by dotted path (see Polyrun::Config::Effective; same tree as YAML plus merged prepare.env, resolved partition shard fields, workers)
            env                  print shard + database env (see polyrun.yml databases)
            db:setup-template    migrate template DB (PostgreSQL)
            db:setup-shard       CREATE DATABASE shard FROM template (one POLYRUN_SHARD_INDEX)
            db:clone-shards      migrate templates + DROP/CREATE all shard DBs (replaces clone_shard shell scripts)
        HELP
      end
    end
  end
end
