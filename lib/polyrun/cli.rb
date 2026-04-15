require "optparse"

require_relative "cli/helpers"
require_relative "cli/plan_command"
require_relative "cli/prepare_command"
require_relative "cli/coverage_commands"
require_relative "cli/report_commands"
require_relative "cli/env_commands"
require_relative "cli/database_commands"
require_relative "cli/run_shards_command"
require_relative "cli/queue_command"
require_relative "cli/timing_command"
require_relative "cli/init_command"
require_relative "cli/quick_command"
require_relative "cli/ci_shard_run_command"

module Polyrun
  class CLI
    CI_SHARD_COMMANDS = {
      "ci-shard-run" => :cmd_ci_shard_run,
      "ci-shard-rspec" => :cmd_ci_shard_rspec
    }.freeze

    include Helpers
    include PlanCommand
    include PrepareCommand
    include CoverageCommands
    include ReportCommands
    include EnvCommands
    include DatabaseCommands
    include RunShardsCommand
    include QueueCommand
    include TimingCommand
    include InitCommand
    include QuickCommand
    include CiShardRunCommand

    def self.run(argv = ARGV)
      new.run(argv)
    end

    def run(argv)
      argv = argv.dup
      config_path = parse_global_cli!(argv)
      return config_path if config_path.is_a?(Integer)

      command = argv.shift
      if command.nil?
        print_help
        return 0
      end

      Polyrun::Debug.log_kv(
        command: command,
        cwd: Dir.pwd,
        polyrun_config: config_path,
        argv_rest: argv.dup,
        verbose: @verbose
      )

      dispatch_cli_command(command, argv, config_path)
    end

    private

    def parse_global_cli!(argv)
      config_path = ENV["POLYRUN_CONFIG"]
      @verbose = false
      while (a = argv.first) && a.start_with?("-") && a != "--"
        case a
        when "-c", "--config"
          argv.shift
          config_path = argv.shift or break
        when "-v", "--verbose"
          @verbose = true
          argv.shift
        when "-h", "--help"
          print_help
          return 0
        else
          break
        end
      end
      config_path
    end

    def dispatch_cli_command(command, argv, config_path)
      case command
      when "help"
        print_help
        0
      when "version"
        cmd_version
      else
        dispatch_cli_command_subcommands(command, argv, config_path)
      end
    end

    def dispatch_cli_command_subcommands(command, argv, config_path)
      case command
      when "plan"
        cmd_plan(argv, config_path)
      when "prepare"
        cmd_prepare(argv, config_path)
      when "merge-coverage"
        cmd_merge_coverage(argv, config_path)
      when "report-coverage"
        cmd_report_coverage(argv)
      when "report-junit"
        cmd_report_junit(argv)
      when "report-timing"
        cmd_report_timing(argv)
      when "env"
        cmd_env(argv, config_path)
      when "merge-timing"
        cmd_merge_timing(argv)
      when "db:setup-template"
        cmd_db_setup_template(argv, config_path)
      when "db:setup-shard"
        cmd_db_setup_shard(argv, config_path)
      when "db:clone-shards"
        cmd_db_clone_shards(argv, config_path)
      when "run-shards"
        cmd_run_shards(argv, config_path)
      when "parallel-rspec"
        cmd_parallel_rspec(argv, config_path)
      when "start"
        cmd_start(argv, config_path)
      when "build-paths"
        cmd_build_paths(config_path)
      when *CI_SHARD_COMMANDS.keys
        send(CI_SHARD_COMMANDS.fetch(command), argv, config_path)
      when "init"
        cmd_init(argv, config_path)
      when "queue"
        cmd_queue(argv)
      when "quick"
        cmd_quick(argv)
      else
        Polyrun::Log.warn "unknown command: #{command}"
        2
      end
    end

    def print_help
      Polyrun::Log.puts <<~HELP
        usage: polyrun [global options] <command> [options]

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
        Parallel RSpec workers: POLYRUN_WORKERS default 5, max 10 (run-shards / parallel-rspec / start)
        Partition timing granularity (default file): POLYRUN_TIMING_GRANULARITY=file|example (experimental per-example; see partition.timing_granularity)

        commands:
          version              print version
          plan                 emit partition manifest JSON
          prepare              run prepare recipe: default | assets (optional prepare.command overrides bin/rails assets:precompile) | shell (prepare.command required)
          merge-coverage       merge SimpleCov JSON fragments (json/lcov/cobertura/console)
          run-shards           fan out N parallel OS processes (POLYRUN_SHARD_*; not Ruby threads); optional --merge-coverage
          parallel-rspec       run-shards + merge-coverage (defaults to: bundle exec rspec after --)
          start                parallel-rspec; auto-runs prepare (shell/assets) and db:setup-* when polyrun.yml configures them; legacy script/build_spec_paths.rb if paths_build absent
          ci-shard-run         CI matrix: build-paths + plan for POLYRUN_SHARD_INDEX / POLYRUN_SHARD_TOTAL (or config), then run your command with that shard's paths after -- (like run-shards; not multi-worker)
          ci-shard-rspec       same as ci-shard-run -- bundle exec rspec; optional -- [rspec-only flags]
          build-paths          write partition.paths_file from partition.paths_build (same as auto step before plan/run-shards)
          init                 write a starter polyrun.yml or POLYRUN.md from built-in templates (see docs/SETUP_PROFILE.md)
          queue                file-backed batch queue (init / claim / ack / status)
          quick                run Polyrun::Quick (describe/it, before/after, let, expect…to, assert_*; optional capybara!)
          report-coverage      write all coverage formats from one JSON file
          report-junit         RSpec JSON or Polyrun testcase JSON → JUnit XML (CI)
          report-timing        print slow-file summary from merged timing JSON
          merge-timing         merge polyrun_timing_*.json shards
          env                  print shard + database env (see polyrun.yml databases)
          db:setup-template    migrate template DB (PostgreSQL)
          db:setup-shard       CREATE DATABASE shard FROM template (one POLYRUN_SHARD_INDEX)
          db:clone-shards      migrate templates + DROP/CREATE all shard DBs (replaces clone_shard shell scripts)
      HELP
    end

    def cmd_version
      Polyrun::Log.puts "polyrun #{Polyrun::VERSION}"
      0
    end
  end
end
