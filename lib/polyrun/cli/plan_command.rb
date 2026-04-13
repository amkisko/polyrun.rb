require "json"
require "optparse"

module Polyrun
  class CLI
    module PlanCommand
      private

      def cmd_plan(argv, config_path)
        cfg = Polyrun::Config.load(path: config_path || ENV["POLYRUN_CONFIG"])
        pc = cfg.partition
        ctx = plan_command_initial_context(pc)
        plan_command_parse_argv!(argv, ctx)

        paths_file = ctx[:paths_file] || (pc["paths_file"] || pc[:paths_file])
        code = Polyrun::Partition::PathsBuild.apply!(partition: pc, cwd: Dir.pwd)
        return code if code != 0

        timing_path = plan_resolve_timing_path(pc, ctx[:timing_path], ctx[:strategy])
        Polyrun::Log.warn "polyrun plan: using #{cfg.path}" if @verbose && cfg.path

        items = plan_plan_items(paths_file, argv)
        return 2 if items.nil?

        loaded = plan_load_costs_and_strategy(timing_path, ctx[:strategy])
        return 2 if loaded.nil?

        costs, strategy = loaded

        constraints = load_partition_constraints(pc, ctx[:constraints_path])

        plan_command_emit_manifest(
          items: items,
          total: ctx[:total],
          strategy: strategy,
          seed: ctx[:seed],
          costs: costs,
          constraints: constraints,
          shard: ctx[:shard]
        )
      end

      def plan_command_initial_context(pc)
        {
          shard: resolve_shard_index(pc),
          total: resolve_shard_total(pc),
          strategy: (pc["strategy"] || pc[:strategy] || "round_robin").to_s,
          seed: pc["seed"] || pc[:seed],
          paths_file: nil,
          timing_path: nil,
          constraints_path: nil
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
        end.parse!(argv)
      end

      def plan_command_emit_manifest(items:, total:, strategy:, seed:, costs:, constraints:, shard:)
        plan = Polyrun::Debug.time("Partition::Plan.new (plan command)") do
          Polyrun::Partition::Plan.new(
            items: items,
            total_shards: total,
            strategy: strategy,
            seed: seed,
            costs: costs,
            constraints: constraints,
            root: Dir.pwd
          )
        end
        Polyrun::Debug.log_kv(
          plan: "emit manifest JSON",
          shard: shard,
          total: total,
          strategy: strategy,
          path_count: items.size
        )
        Polyrun::Log.puts JSON.generate(plan.manifest(shard))
        0
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

      def plan_load_costs_and_strategy(timing_path, strategy)
        if timing_path
          costs = Polyrun::Partition::Plan.load_timing_costs(File.expand_path(timing_path.to_s, Dir.pwd))
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
