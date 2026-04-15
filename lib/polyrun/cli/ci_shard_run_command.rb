require "shellwords"

module Polyrun
  class CLI
    # One CI matrix job = one global shard (POLYRUN_SHARD_INDEX / POLYRUN_SHARD_TOTAL), not +run-shards+
    # workers on a single host. Runs +build-paths+, +plan+ for that shard, then +exec+ of a user command
    # with that shard's paths appended (same argv pattern as +run-shards+ after +--+).
    #
    # After +--+, prefer **multiple argv tokens** (+bundle+, +exec+, +rspec+, …). A single token that
    # contains spaces is split with +Shellwords+ (not a full shell); exotic quoting differs from +sh -c+.
    module CiShardRunCommand
      private

      # @return [Array(Array<String>, Integer)] [paths, 0] on success, or [nil, exit_code] on failure
      def ci_shard_planned_paths!(plan_argv, config_path, command_label:)
        manifest, code = plan_command_compute_manifest(plan_argv, config_path)
        return [nil, code] if code != 0

        paths = manifest["paths"] || []
        if paths.empty?
          Polyrun::Log.warn "polyrun #{command_label}: no paths for this shard (check shard/total and paths list)"
          return [nil, 2]
        end

        [paths, 0]
      end

      # Runner-agnostic matrix shard: +polyrun ci-shard-run [plan options] -- <command> [args...]+
      # Paths for this shard are appended after the command (like +run-shards+).
      def cmd_ci_shard_run(argv, config_path)
        sep = argv.index("--")
        unless sep
          Polyrun::Log.warn "polyrun ci-shard-run: need -- before the command (e.g. ci-shard-run -- bundle exec rspec)"
          return 2
        end

        plan_argv = argv[0...sep]
        cmd = argv[(sep + 1)..].map(&:to_s)
        if cmd.empty?
          Polyrun::Log.warn "polyrun ci-shard-run: empty command after --"
          return 2
        end
        cmd = Shellwords.split(cmd.first) if cmd.size == 1 && cmd.first.include?(" ")

        paths, code = ci_shard_planned_paths!(plan_argv, config_path, command_label: "ci-shard-run")
        return code if code != 0

        exec(*cmd, *paths)
      end

      # Same as +ci-shard-run -- bundle exec rspec+ with an optional second segment for RSpec-only flags:
      # +polyrun ci-shard-rspec [plan options] [-- [rspec args]]+
      def cmd_ci_shard_rspec(argv, config_path)
        sep = argv.index("--")
        plan_argv = sep ? argv[0...sep] : argv
        rspec_argv = sep ? argv[(sep + 1)..] : []

        paths, code = ci_shard_planned_paths!(plan_argv, config_path, command_label: "ci-shard-rspec")
        return code if code != 0

        exec("bundle", "exec", "rspec", *rspec_argv, *paths)
      end
    end
  end
end
