require "shellwords"

module Polyrun
  class CLI
    # Boot argv, then phase A (options + validate) and B (items + plan) for run-shards.
    module RunShardsPlanBootPhases
      private

      # @return [:fail, Integer] | [:ok, Hash, Array<String>]
      def run_shards_plan_phase_a(head, cmd, pc)
        o = run_shards_plan_options(head, pc)
        code = Polyrun::Partition::PathsBuild.apply!(partition: pc, cwd: Dir.pwd)
        return [:fail, code] if code != 0

        o[:timing_path] = run_shards_default_timing_path(pc, o[:timing_path], o[:strategy])
        err = run_shards_validate_workers!(o)
        return [:fail, err] if err

        err = run_shards_validate_cmd(cmd)
        return [:fail, err] if err

        run_shards_normalize_worker_timeout_option!(o)
        run_shards_normalize_worker_idle_timeout_option!(o)

        cmd = Shellwords.split(cmd.first) if cmd.size == 1 && cmd.first.include?(" ")

        [:ok, o, cmd]
      end

      def run_shards_plan_phase_b(o, cmd, cfg, pc, run_t0, config_path)
        items, paths_source, err = run_shards_resolve_items(o[:paths_file], pc)
        return [err, nil] if err

        costs, strategy, err = run_shards_resolve_costs(o[:timing_path], o[:strategy], o[:timing_granularity])
        return [err, nil] if err

        run_shards_plan_ready_log(o, cfg, strategy, cmd, paths_source, items.size)

        constraints = load_partition_constraints(pc, o[:constraints_path])
        plan = run_shards_make_plan(items, o[:workers], strategy, o[:seed], costs, constraints, o[:timing_granularity])

        run_shards_debug_shard_sizes(plan, o[:workers])
        Polyrun::Log.warn "polyrun run-shards: #{items.size} paths → #{o[:workers]} workers (#{strategy})" if @verbose

        parallel = o[:workers] > 1
        run_shards_warn_parallel_banner(items.size, o[:workers], strategy) if parallel

        [nil, run_shards_plan_context_hash(o, cmd, cfg, plan, run_t0, parallel, config_path)]
      end

      def run_shards_plan_boot(argv, config_path)
        run_t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        sep = argv.index("--")
        unless sep
          Polyrun::Log.warn "polyrun run-shards: need -- before the command (e.g. run-shards --workers 5 -- bundle exec rspec)"
          return [2, nil]
        end

        head = argv[0...sep]
        cmd = argv[(sep + 1)..].map(&:to_s)
        cfg = Polyrun::Config.load(path: config_path || ENV["POLYRUN_CONFIG"])
        [run_t0, head, cmd, cfg, cfg.partition]
      end

      def run_shards_plan_ready_log(o, cfg, strategy, cmd, paths_source, item_count)
        Polyrun::Debug.log_kv(
          run_shards: "ready to partition",
          workers: o[:workers],
          strategy: strategy,
          merge_coverage: o[:merge_coverage],
          merge_failures: run_shards_merge_failures_flag(o, cfg),
          command: cmd,
          timing_path: o[:timing_path],
          paths_source: paths_source,
          item_count: item_count
        )
      end

      def run_shards_merge_failures_flag(o, cfg)
        return true if o[:merge_failures]
        return true if %w[1 true yes].include?(ENV["POLYRUN_MERGE_FAILURES"].to_s.downcase)

        rep = cfg.reporting
        v = rep["merge_failures"] || rep[:merge_failures]
        v == true || %w[1 true yes].include?(v.to_s.downcase)
      end

      def run_shards_merge_failures_output_opt(o, cfg)
        x = o[:merge_failures_output]
        return x if x && !x.to_s.strip.empty?

        x = ENV["POLYRUN_MERGED_FAILURES_OUT"]
        return x if x && !x.to_s.strip.empty?

        rep = cfg.reporting
        rep["merge_failures_output"] || rep[:merge_failures_output]
      end

      def run_shards_merge_failures_format_opt(o, cfg)
        x = o[:merge_failures_format]
        return x if x && !x.to_s.strip.empty?

        x = ENV["POLYRUN_MERGED_FAILURES_FORMAT"]
        return x if x && !x.to_s.strip.empty?

        rep = cfg.reporting
        rep["merge_failures_format"] || rep[:merge_failures_format]
      end

      def run_shards_plan_context_hash(o, cmd, cfg, plan, run_t0, parallel, config_path)
        {
          workers: o[:workers],
          cmd: cmd,
          cfg: cfg,
          plan: plan,
          run_t0: run_t0,
          parallel: parallel,
          merge_coverage: o[:merge_coverage],
          merge_output: o[:merge_output],
          merge_format: o[:merge_format],
          merge_failures: run_shards_merge_failures_flag(o, cfg),
          merge_failures_output: run_shards_merge_failures_output_opt(o, cfg),
          merge_failures_format: run_shards_merge_failures_format_opt(o, cfg),
          config_path: config_path,
          worker_timeout_sec: run_shards_resolved_worker_timeout_sec(o),
          worker_idle_timeout_sec: run_shards_resolved_worker_idle_timeout_sec(o)
        }
      end

      def run_shards_normalize_worker_idle_timeout_option!(o)
        v = o[:worker_idle_timeout_sec]
        return if v.nil?

        o[:worker_idle_timeout_sec] = nil if v <= 0
      end

      def run_shards_resolved_worker_idle_timeout_sec(o)
        cli = o[:worker_idle_timeout_sec]
        return cli.to_f if cli.is_a?(Numeric) && cli > 0

        env_worker_idle_timeout_sec
      end

      def run_shards_normalize_worker_timeout_option!(o)
        v = o[:worker_timeout_sec]
        return if v.nil?

        o[:worker_timeout_sec] = nil if v <= 0
      end

      def run_shards_resolved_worker_timeout_sec(o)
        cli = o[:worker_timeout_sec]
        return cli.to_f if cli.is_a?(Numeric) && cli > 0

        env_worker_timeout_sec
      end
    end
  end
end
