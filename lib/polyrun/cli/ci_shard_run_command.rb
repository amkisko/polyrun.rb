require "shellwords"

module Polyrun
  class CLI
    # One CI matrix job = one global shard (POLYRUN_SHARD_INDEX / POLYRUN_SHARD_TOTAL), not +run-shards+
    # workers on a single host. Runs +build-paths+, +plan+ for that shard, then +exec+ of a user command
    # with that shard's paths appended (same argv pattern as +run-shards+ after +--+).
    #
    # With +--shard-processes M+ (or +partition.shard_processes+ / +POLYRUN_SHARD_PROCESSES+), fans out
    # +M+ OS processes on this host, each running a subset of this shard's paths (NxM: +N+ matrix jobs × +M+
    # processes). Child processes get local +POLYRUN_SHARD_INDEX+ / +POLYRUN_SHARD_TOTAL+ (+0..M-1+, +M+);
    # when +N+ > 1, also +POLYRUN_SHARD_MATRIX_INDEX+ / +POLYRUN_SHARD_MATRIX_TOTAL+ for unique coverage fragments.
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

      def ci_shard_local_plan!(paths, workers)
        Polyrun::Partition::Plan.new(
          items: paths,
          total_shards: workers,
          strategy: "round_robin",
          root: Dir.pwd
        )
      end

      # When +N+ > 1 and +M+ > 1, pass matrix index/total for coverage fragment names; else nil (see +shard_child_env+).
      def ci_shard_matrix_context(pc, shard_processes)
        n = resolve_shard_total(pc)
        return [nil, nil] if n <= 1 || shard_processes <= 1

        [resolve_shard_index(pc), n]
      end

      def ci_shard_run_fanout!(ctx)
        pids = run_shards_spawn_workers(ctx)
        return 1 if pids.empty?

        run_shards_warn_interleaved(ctx[:parallel], pids.size)
        shard_results = run_shards_wait_all_children(pids)
        failed = shard_results.reject { |r| r[:success] }.map { |r| r[:shard] }

        if failed.any?
          Polyrun::Log.warn "polyrun ci-shard: finished #{pids.size} worker(s) (some failed)"
          run_shards_log_failed_reruns(failed, shard_results, ctx[:plan], ctx[:parallel], ctx[:workers], ctx[:cmd])
          return 1
        end

        Polyrun::Log.warn "polyrun ci-shard: finished #{pids.size} worker(s) (exit 0)"
        0
      end

      def ci_shard_fanout_context(cfg:, pc:, paths:, shard_processes:, cmd:, config_path:)
        plan = ci_shard_local_plan!(paths, shard_processes)
        mx, mt = ci_shard_matrix_context(pc, shard_processes)
        {
          workers: shard_processes,
          cmd: cmd,
          cfg: cfg,
          plan: plan,
          run_t0: Process.clock_gettime(Process::CLOCK_MONOTONIC),
          parallel: true,
          merge_coverage: false,
          merge_output: nil,
          merge_format: nil,
          config_path: config_path,
          matrix_shard_index: mx,
          matrix_shard_total: mt
        }
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

        cfg = Polyrun::Config.load(path: config_path || ENV["POLYRUN_CONFIG"])
        pc = cfg.partition
        shard_processes, perr = ci_shard_parse_shard_processes!(plan_argv, pc)
        return perr if perr

        shard_processes, err = ci_shard_normalize_shard_processes(shard_processes)
        return err if err

        paths, code = ci_shard_planned_paths!(plan_argv, config_path, command_label: "ci-shard-run")
        return code if code != 0

        if shard_processes <= 1
          exec(*cmd, *paths)
          return 0
        end

        ctx = ci_shard_fanout_context(
          cfg: cfg, pc: pc, paths: paths, shard_processes: shard_processes, cmd: cmd, config_path: config_path
        )
        Polyrun::Log.warn "polyrun ci-shard-run: #{paths.size} path(s) → #{shard_processes} process(es) on this host (NxM: matrix jobs × local processes)"
        ci_shard_run_fanout!(ctx)
      end

      # Same as +ci-shard-run -- bundle exec rspec+ with an optional second segment for RSpec-only flags:
      # +polyrun ci-shard-rspec [plan options] [-- [rspec args]]+
      def cmd_ci_shard_rspec(argv, config_path)
        sep = argv.index("--")
        plan_argv = sep ? argv[0...sep] : argv
        rspec_argv = sep ? argv[(sep + 1)..] : []

        cfg = Polyrun::Config.load(path: config_path || ENV["POLYRUN_CONFIG"])
        pc = cfg.partition
        shard_processes, perr = ci_shard_parse_shard_processes!(plan_argv, pc)
        return perr if perr

        shard_processes, err = ci_shard_normalize_shard_processes(shard_processes)
        return err if err

        paths, code = ci_shard_planned_paths!(plan_argv, config_path, command_label: "ci-shard-rspec")
        return code if code != 0

        cmd = ["bundle", "exec", "rspec", *rspec_argv]

        if shard_processes <= 1
          exec(*cmd, *paths)
          return 0
        end

        ctx = ci_shard_fanout_context(
          cfg: cfg, pc: pc, paths: paths, shard_processes: shard_processes, cmd: cmd, config_path: config_path
        )
        Polyrun::Log.warn "polyrun ci-shard-rspec: #{paths.size} path(s) → #{shard_processes} process(es) on this host (NxM: matrix jobs × local processes)"
        ci_shard_run_fanout!(ctx)
      end
    end
  end
end
