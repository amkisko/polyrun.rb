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
require_relative "cli/config_command"
require_relative "cli/default_run"
require_relative "cli/help"

module Polyrun
  class CLI
    CI_SHARD_COMMANDS = {
      "ci-shard-run" => :cmd_ci_shard_run,
      "ci-shard-rspec" => :cmd_ci_shard_rspec
    }.freeze

    # Keep in sync with +dispatch_cli_command_subcommands+ (+when+ branches). Used for implicit path routing.
    DISPATCH_SUBCOMMAND_NAMES = %w[
      plan prepare merge-coverage report-coverage report-junit report-timing
      env config merge-timing db:setup-template db:setup-shard db:clone-shards
      run-shards parallel-rspec start build-paths init queue quick
    ].freeze

    # First argv token that is a normal subcommand (not a path); if argv[0] is not here but looks like paths, run implicit parallel.
    IMPLICIT_PATH_EXCLUSION_TOKENS = (
      DISPATCH_SUBCOMMAND_NAMES + CI_SHARD_COMMANDS.keys + %w[help version]
    ).freeze

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
    include ConfigCommand
    include DefaultRun
    include Help

    def self.run(argv = ARGV)
      new.run(argv)
    end

    def run(argv)
      argv = argv.dup
      config_path = parse_global_cli!(argv)
      return config_path if config_path.is_a?(Integer)

      if argv.empty?
        Polyrun::Debug.log_kv(
          command: "(default)",
          cwd: Dir.pwd,
          polyrun_config: config_path,
          argv_rest: [],
          verbose: @verbose
        )
        return dispatch_default_parallel!(config_path)
      end

      if implicit_parallel_run?(argv)
        Polyrun::Debug.log_kv(
          command: "(paths)",
          cwd: Dir.pwd,
          polyrun_config: config_path,
          argv_rest: argv.dup,
          verbose: @verbose
        )
        return dispatch_implicit_parallel_targets!(argv, config_path)
      end

      command = argv.shift

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

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity -- explicit dispatch table
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
      when "config"
        cmd_config(argv, config_path)
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
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity

    def cmd_version
      Polyrun::Log.puts "polyrun #{Polyrun::VERSION}"
      0
    end
  end
end
