require "optparse"

module Polyrun
  class CLI
    module RunShardsPlanOptions
      private

      def run_shards_plan_options(head, pc)
        st = run_shards_plan_options_state(pc)
        run_shards_plan_options_parse!(head, st)
        st[:paths_file] ||= pc["paths_file"] || pc[:paths_file]
        st[:timing_granularity] = resolve_partition_timing_granularity(pc, st[:timing_granularity])
        st
      end

      def run_shards_plan_options_state(pc)
        {
          workers: env_int("POLYRUN_WORKERS", Polyrun::Config::DEFAULT_PARALLEL_WORKERS),
          paths_file: nil,
          strategy: (pc["strategy"] || pc[:strategy] || "round_robin").to_s,
          seed: pc["seed"] || pc[:seed],
          timing_path: nil,
          constraints_path: nil,
          timing_granularity: nil,
          merge_coverage: false,
          merge_output: nil,
          merge_format: nil
        }
      end

      def run_shards_plan_options_parse!(head, st)
        OptionParser.new do |opts|
          run_shards_plan_options_register!(opts, st)
        end.parse!(head)
      end

      def run_shards_plan_options_register!(opts, st)
        opts.banner = "usage: polyrun run-shards [--workers N] [--strategy NAME] [--paths-file P] [--timing P] [--timing-granularity VAL] [--constraints P] [--seed S] [--merge-coverage] [--merge-output P] [--merge-format LIST] [--] <command> [args...]"
        opts.on("--workers N", Integer) { |v| st[:workers] = v }
        opts.on("--strategy NAME", String) { |v| st[:strategy] = v }
        opts.on("--seed VAL") { |v| st[:seed] = v }
        opts.on("--paths-file PATH", String) { |v| st[:paths_file] = v }
        opts.on("--constraints PATH", String) { |v| st[:constraints_path] = v }
        opts.on("--timing PATH", "merged polyrun_timing.json; implies cost_binpack unless hrw/cost") { |v| st[:timing_path] = v }
        opts.on("--timing-granularity VAL", "file (default) or example (experimental)") { |v| st[:timing_granularity] = v }
        opts.on("--merge-coverage", "After success, merge coverage/polyrun-fragment-*.json (Polyrun coverage must be enabled)") { st[:merge_coverage] = true }
        opts.on("--merge-output PATH", String) { |v| st[:merge_output] = v }
        opts.on("--merge-format LIST", String) { |v| st[:merge_format] = v }
      end
    end
  end
end
