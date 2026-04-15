require_relative "run_shards_plan_options"
require_relative "run_shards_plan_boot_phases"

module Polyrun
  class CLI
    # Parses argv, loads config, builds {Partition::Plan} for run-shards.
    module RunShardsPlanning
      include RunShardsPlanOptions
      include RunShardsPlanBootPhases

      private

      # @return [Array(Integer, Hash, nil)] [exit_code, nil] on failure, or [nil, ctx] on success
      def run_shards_build_plan(argv, config_path)
        boot = run_shards_plan_boot(argv, config_path)
        return boot if boot.size == 2

        run_t0, head, cmd, cfg, pc = boot
        phase = run_shards_plan_phase_a(head, cmd, pc)
        return [phase[1], nil] if phase[0] == :fail

        _tag, o, cmd = phase
        run_shards_plan_phase_b(o, cmd, cfg, pc, run_t0, config_path)
      end

      def run_shards_default_timing_path(pc, timing_path, strategy)
        return timing_path if timing_path

        tf = pc["timing_file"] || pc[:timing_file]
        return tf if tf && (Polyrun::Partition::Plan.cost_strategy?(strategy) || Polyrun::Partition::Plan.hrw_strategy?(strategy))

        nil
      end

      def run_shards_validate_workers!(o)
        w = o[:workers]
        if w < 1
          Polyrun::Log.warn "polyrun run-shards: --workers must be >= 1"
          return 2
        end
        if w > Polyrun::Config::MAX_PARALLEL_WORKERS
          Polyrun::Log.warn "polyrun run-shards: capping --workers / POLYRUN_WORKERS from #{w} to #{Polyrun::Config::MAX_PARALLEL_WORKERS}"
          o[:workers] = Polyrun::Config::MAX_PARALLEL_WORKERS
        end
        nil
      end

      def run_shards_validate_cmd(cmd)
        if cmd.empty?
          Polyrun::Log.warn "polyrun run-shards: empty command after --"
          return 2
        end
        nil
      end

      def run_shards_resolve_items(paths_file, partition)
        resolved = Polyrun::Partition::Paths.resolve_run_shard_items(paths_file: paths_file, partition: partition)
        if resolved[:error]
          Polyrun::Log.warn "polyrun run-shards: #{resolved[:error]}"
          return [nil, nil, 2]
        end
        items = resolved[:items]
        paths_source = resolved[:source]
        Polyrun::Log.warn "polyrun run-shards: #{items.size} path(s) from #{paths_source}"

        if items.empty?
          Polyrun::Log.warn "polyrun run-shards: no paths (empty paths file or list)"
          return [nil, nil, 2]
        end
        [items, paths_source, nil]
      end

      def run_shards_resolve_costs(timing_path, strategy, timing_granularity)
        if timing_path
          costs = Polyrun::Partition::Plan.load_timing_costs(
            File.expand_path(timing_path.to_s, Dir.pwd),
            granularity: timing_granularity
          )
          if costs.empty?
            Polyrun::Log.warn "polyrun run-shards: timing file missing or empty: #{timing_path}"
            return [nil, nil, 2]
          end
          unless Polyrun::Partition::Plan.cost_strategy?(strategy) || Polyrun::Partition::Plan.hrw_strategy?(strategy)
            Polyrun::Log.warn "polyrun run-shards: using cost_binpack (timing data present)" if @verbose
            strategy = "cost_binpack"
          end
          [costs, strategy, nil]
        elsif Polyrun::Partition::Plan.cost_strategy?(strategy)
          Polyrun::Log.warn "polyrun run-shards: --timing or partition.timing_file required for strategy #{strategy}"
          [nil, nil, 2]
        else
          [nil, strategy, nil]
        end
      end

      def run_shards_make_plan(items, workers, strategy, seed, costs, constraints, timing_granularity)
        Polyrun::Debug.time("Partition::Plan.new (partition #{items.size} paths → #{workers} shards)") do
          Polyrun::Partition::Plan.new(
            items: items,
            total_shards: workers,
            strategy: strategy,
            seed: seed,
            costs: costs,
            constraints: constraints,
            root: Dir.pwd,
            timing_granularity: timing_granularity
          )
        end
      end

      def run_shards_debug_shard_sizes(plan, workers)
        return unless Polyrun::Debug.enabled?

        workers.times do |s|
          n = plan.shard(s).size
          Polyrun::Debug.log("run-shards: shard #{s} → #{n} spec file(s)")
        end
      end

      def run_shards_warn_parallel_banner(item_count, workers, strategy)
        Polyrun::Log.warn <<~MSG
          polyrun run-shards: #{item_count} path(s) -> #{workers} parallel worker processes (not Ruby threads); strategy=#{strategy}
          (plain `bundle exec rspec` is one process; this command fans out.)
        MSG
      end
    end
  end
end
