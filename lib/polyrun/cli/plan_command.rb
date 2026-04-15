require "json"
require "optparse"

module Polyrun
  class CLI
    module PlanCommand
      private

      def cmd_plan(argv, config_path)
        manifest, code = plan_command_compute_manifest(argv, config_path)
        return code if code != 0

        Polyrun::Log.puts JSON.generate(manifest)
        0
      end

      # @return [Array(Hash, Integer)] manifest hash and exit code (+0+ on success, non-zero on failure)
      def plan_command_compute_manifest(argv, config_path)
        cfg = Polyrun::Config.load(path: config_path || ENV["POLYRUN_CONFIG"])
        pc = cfg.partition
        ctx = plan_command_initial_context(pc)
        plan_command_parse_argv!(argv, ctx)

        paths_file = ctx[:paths_file] || (pc["paths_file"] || pc[:paths_file])
        code = Polyrun::Partition::PathsBuild.apply!(partition: pc, cwd: Dir.pwd)
        return [nil, code] if code != 0

        plan_command_manifest_from_paths(cfg, pc, argv, ctx, paths_file)
      end

      def plan_command_manifest_from_paths(cfg, pc, argv, ctx, paths_file)
        timing_path = plan_resolve_timing_path(pc, ctx[:timing_path], ctx[:strategy])
        ctx[:timing_granularity] = resolve_partition_timing_granularity(pc, ctx[:timing_granularity])
        Polyrun::Log.warn "polyrun plan: using #{cfg.path}" if @verbose && cfg.path

        bundle = plan_command_items_costs_strategy(paths_file, argv, timing_path, ctx)
        return [nil, 2] if bundle.nil?

        items, costs, strategy = bundle
        constraints = load_partition_constraints(pc, ctx[:constraints_path])

        manifest = plan_command_build_manifest(
          items: items,
          total: ctx[:total],
          strategy: strategy,
          seed: ctx[:seed],
          costs: costs,
          constraints: constraints,
          shard: ctx[:shard],
          timing_granularity: ctx[:timing_granularity]
        )
        [manifest, 0]
      end

      def plan_command_items_costs_strategy(paths_file, argv, timing_path, ctx)
        items = plan_plan_items(paths_file, argv)
        return nil if items.nil?

        loaded = plan_load_costs_and_strategy(timing_path, ctx[:strategy], ctx[:timing_granularity])
        return nil if loaded.nil?

        costs, strategy = loaded
        [items, costs, strategy]
      end

      def plan_command_initial_context(pc)
        {
          shard: resolve_shard_index(pc),
          total: resolve_shard_total(pc),
          strategy: (pc["strategy"] || pc[:strategy] || "round_robin").to_s,
          seed: pc["seed"] || pc[:seed],
          paths_file: nil,
          timing_path: nil,
          constraints_path: nil,
          timing_granularity: nil
        }
      end

      def plan_command_parse_argv!(argv, ctx)
        OptionParser.new do |opts|
          opts.banner = "usage: polyrun plan [options] [--] [paths...]"
          opts.on("--shard INDEX", Integer) { |v| ctx[:shard] = v }
          opts.on("--total N", Integer) { |v| ctx[:total] = v }
          opts.on("--strategy NAME", String) { |v| ctx[:strategy] = v }
          opts.on("--seed VAL") { |v| ctx[:seed] = v }
          opts.on("--paths-file PATH", String) { |v| ctx[:paths_file] = v }
          opts.on("--constraints PATH", "YAML: pin / serial_glob (see spec_queue.md)") { |v| ctx[:constraints_path] = v }
          opts.on("--timing PATH", "path => seconds JSON; implies cost_binpack unless strategy is cost-based or hrw") do |v|
            ctx[:timing_path] = v
          end
          opts.on("--timing-granularity VAL", "file (default) or example (experimental: path:line items)") do |v|
            ctx[:timing_granularity] = v
          end
        end.parse!(argv)
      end

      def plan_command_build_manifest(items:, total:, strategy:, seed:, costs:, constraints:, shard:, timing_granularity: :file)
        plan = Polyrun::Debug.time("Partition::Plan.new (plan command)") do
          Polyrun::Partition::Plan.new(
            items: items,
            total_shards: total,
            strategy: strategy,
            seed: seed,
            costs: costs,
            constraints: constraints,
            root: Dir.pwd,
            timing_granularity: timing_granularity
          )
        end
        Polyrun::Debug.log_kv(
          plan: "emit manifest JSON",
          shard: shard,
          total: total,
          strategy: strategy,
          path_count: items.size
        )
        plan.manifest(shard)
      end

      def plan_resolve_timing_path(pc, timing_path, strategy)
        return timing_path if timing_path

        tf = pc["timing_file"] || pc[:timing_file]
        return tf if tf && (Polyrun::Partition::Plan.cost_strategy?(strategy) || Polyrun::Partition::Plan.hrw_strategy?(strategy))

        nil
      end

      def plan_plan_items(paths_file, argv)
        if paths_file
          Polyrun::Partition::Paths.read_lines(paths_file)
        elsif argv.empty?
          Polyrun::Log.warn "polyrun plan: provide spec paths, --paths-file, or partition.paths_file in polyrun.yml"
          nil
        else
          argv
        end
      end

      def plan_load_costs_and_strategy(timing_path, strategy, timing_granularity)
        if timing_path
          costs = Polyrun::Partition::Plan.load_timing_costs(
            File.expand_path(timing_path.to_s, Dir.pwd),
            granularity: timing_granularity
          )
          if costs.empty?
            Polyrun::Log.warn "polyrun plan: timing file missing or has no entries: #{timing_path}"
            return nil
          end
          unless Polyrun::Partition::Plan.cost_strategy?(strategy) || Polyrun::Partition::Plan.hrw_strategy?(strategy)
            Polyrun::Log.warn "polyrun plan: using cost_binpack (timing data present)" if @verbose
            strategy = "cost_binpack"
          end
          [costs, strategy]
        elsif Polyrun::Partition::Plan.cost_strategy?(strategy)
          Polyrun::Log.warn "polyrun plan: --timing or partition.timing_file required for strategy #{strategy}"
          nil
        else
          [nil, strategy]
        end
      end
    end
  end
end
