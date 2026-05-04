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
          merge_format: nil,
          merge_failures: false,
          merge_failures_output: nil,
          merge_failures_format: nil,
          worker_timeout_sec: nil,
          worker_idle_timeout_sec: nil
        }
      end

      def run_shards_plan_options_parse!(head, st)
        OptionParser.new do |opts|
          run_shards_plan_options_register!(opts, st)
        end.parse!(head)
      end

      # rubocop:disable Metrics/AbcSize -- one argv block for run-shards
      def run_shards_plan_options_register!(opts, st)
        opts.banner = "usage: polyrun run-shards [--workers N] [--worker-timeout SEC] [--worker-idle-timeout SEC] [--strategy NAME] [--paths-file P] [--timing P] [--timing-granularity VAL] [--constraints P] [--seed S] [--merge-coverage] [--merge-output P] [--merge-format LIST] [--merge-failures] [--merge-failures-output P] [--merge-failures-format jsonl|json] [--] <command> [args...]"
        opts.on("--workers N", Integer) { |v| st[:workers] = v }
        opts.on("--worker-timeout SEC", Float, "Max seconds per worker since spawn (also POLYRUN_WORKER_TIMEOUT_SEC); kills stuck workers (exit 124)") { |v| st[:worker_timeout_sec] = v }
        opts.on("--worker-idle-timeout SEC", Float, "Max seconds since last valid WorkerPing timestamp in POLYRUN_WORKER_PING_FILE (needs prior ping); RSpec/Minitest: install_worker_ping!; Quick: automatic; exit 125") { |v| st[:worker_idle_timeout_sec] = v }
        opts.on("--strategy NAME", String) { |v| st[:strategy] = v }
        opts.on("--seed VAL") { |v| st[:seed] = v }
        opts.on("--paths-file PATH", String) { |v| st[:paths_file] = v }
        opts.on("--constraints PATH", String) { |v| st[:constraints_path] = v }
        opts.on("--timing PATH", "merged polyrun_timing.json; implies cost_binpack unless hrw/cost") { |v| st[:timing_path] = v }
        opts.on("--timing-granularity VAL", "file (default) or example (experimental)") { |v| st[:timing_granularity] = v }
        opts.on("--merge-coverage", "After success, merge coverage/polyrun-fragment-*.json (Polyrun coverage must be enabled)") { st[:merge_coverage] = true }
        opts.on("--merge-output PATH", String) { |v| st[:merge_output] = v }
        opts.on("--merge-format LIST", String) { |v| st[:merge_format] = v }
        opts.on("--merge-failures", "After all workers exit, merge tmp/polyrun_failures/polyrun-failure-fragment-*.jsonl (use Polyrun::RSpec.install_failure_fragments!)") { st[:merge_failures] = true }
        opts.on("--merge-failures-output PATH", String) { |v| st[:merge_failures_output] = v }
        opts.on("--merge-failures-format VAL", "jsonl (default) or json") { |v| st[:merge_failures_format] = v }
      end
      # rubocop:enable Metrics/AbcSize
    end
  end
end
