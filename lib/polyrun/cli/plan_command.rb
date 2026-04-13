require "json"
require "optparse"

module Polyrun
  class CLI
    module PlanCommand
      private

      def cmd_plan(argv, config_path)
        cfg = Polyrun::Config.load(path: config_path || ENV["POLYRUN_CONFIG"])
        pc = cfg.partition
        shard = resolve_shard_index(pc)
        total = resolve_shard_total(pc)
        strategy = (pc["strategy"] || pc[:strategy] || "round_robin").to_s
        seed = pc["seed"] || pc[:seed]
        config_paths_file = pc["paths_file"] || pc[:paths_file]
        paths_file = nil
        timing_path = nil
        constraints_path = nil

        parser = OptionParser.new do |opts|
          opts.banner = "usage: polyrun plan [options] [--] [paths...]"
          opts.on("--shard INDEX", Integer) { |v| shard = v }
          opts.on("--total N", Integer) { |v| total = v }
          opts.on("--strategy NAME", String) { |v| strategy = v }
          opts.on("--seed VAL") { |v| seed = v }
          opts.on("--paths-file PATH", String) { |v| paths_file = v }
          opts.on("--constraints PATH", "YAML: pin / serial_glob (see spec_queue.md)") { |v| constraints_path = v }
          opts.on("--timing PATH", "path => seconds JSON; implies cost_binpack unless strategy is cost-based or hrw") do |v|
            timing_path = v
          end
        end
        parser.parse!(argv)

        paths_file ||= config_paths_file
        code = Polyrun::Partition::PathsBuild.apply!(partition: pc, cwd: Dir.pwd)
        return code if code != 0

        unless timing_path
          tf = pc["timing_file"] || pc[:timing_file]
          if tf && (Polyrun::Partition::Plan.cost_strategy?(strategy) || Polyrun::Partition::Plan.hrw_strategy?(strategy))
            timing_path = tf
          end
        end
        Polyrun::Log.warn "polyrun plan: using #{cfg.path}" if @verbose && cfg.path

        items =
          if paths_file
            Polyrun::Partition::Paths.read_lines(paths_file)
          elsif argv.empty?
            Polyrun::Log.warn "polyrun plan: provide spec paths, --paths-file, or partition.paths_file in polyrun.yml"
            return 2
          else
            argv
          end

        costs = nil
        if timing_path
          costs = Polyrun::Partition::Plan.load_timing_costs(File.expand_path(timing_path.to_s, Dir.pwd))
          if costs.empty?
            Polyrun::Log.warn "polyrun plan: timing file missing or has no entries: #{timing_path}"
            return 2
          end
          unless Polyrun::Partition::Plan.cost_strategy?(strategy) || Polyrun::Partition::Plan.hrw_strategy?(strategy)
            Polyrun::Log.warn "polyrun plan: using cost_binpack (timing data present)" if @verbose
            strategy = "cost_binpack"
          end
        elsif Polyrun::Partition::Plan.cost_strategy?(strategy)
          Polyrun::Log.warn "polyrun plan: --timing or partition.timing_file required for strategy #{strategy}"
          return 2
        end

        constraints = load_partition_constraints(pc, constraints_path)

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
    end
  end
end
