require "shellwords"
require "rbconfig"

require_relative "run_shards_planning"
require_relative "run_shards_worker_interrupt"
require_relative "run_shards_parallel_children"

module Polyrun
  class CLI
    # Partition + spawn workers for `polyrun run-shards` (keeps {RunShardsCommand} file small).
    module RunShardsRun
      include RunShardsPlanning
      include RunShardsWorkerInterrupt
      include RunShardsParallelChildren

      private

      def run_shards_run!(argv, config_path)
        code, ctx = run_shards_build_plan(argv, config_path)
        return code if code

        run_shards_workers_and_merge(ctx)
      end

      # rubocop:disable Metrics/AbcSize -- orchestration: hooks, merge, worker failures
      def run_shards_workers_and_merge(ctx)
        hook_cfg = Polyrun::Hooks.from_config(ctx[:cfg])
        suite_started = false
        exit_code = 1
        merged_failures_path = nil
        merge_failures_errored = false

        begin
          env_suite = ENV.to_h.merge(
            "POLYRUN_HOOK_ORCHESTRATOR" => "1",
            "POLYRUN_SHARD_TOTAL" => ctx[:workers].to_s
          )
          code = hook_cfg.run_phase_if_enabled(:before_suite, env_suite)
          return code if code != 0

          suite_started = true

          pids, spawn_err = run_shards_spawn_workers(ctx, hook_cfg)
          if spawn_err
            exit_code = spawn_err
            return spawn_err
          end
          if pids.empty?
            exit_code = 1
            return 1
          end

          run_shards_warn_interleaved(ctx[:parallel], pids.size)

          shard_results, wait_hook_err = run_shards_wait_all_children(pids, hook_cfg, ctx)
          failed = shard_results.reject { |r| r[:success] }.map { |r| r[:shard] }

          Polyrun::Debug.log(format(
            "run-shards: workers wall time since start: %.3fs",
            Process.clock_gettime(Process::CLOCK_MONOTONIC) - ctx[:run_t0]
          ))

          if ctx[:parallel]
            Polyrun::Log.warn "polyrun run-shards: finished #{pids.size} worker(s)" + (failed.any? ? " (some failed)" : " (exit 0)")
          end

          if ctx[:merge_failures]
            begin
              merged_failures_path = merge_failures_after_shards(ctx)
            rescue Polyrun::Error => e
              Polyrun::Log.warn e.message.to_s
              merge_failures_errored = true
            end
          end

          if failed.any?
            run_shards_log_failed_reruns(
              failed, shard_results, ctx[:plan], ctx[:parallel], ctx[:workers], ctx[:cmd],
              merge_failures: ctx[:merge_failures]
            )
            exit_code = 1
            exit_code = 1 if wait_hook_err != 0
            return exit_code
          end

          exit_code = run_shards_merge_or_hint_coverage(ctx)
          exit_code = 1 if wait_hook_err != 0 && exit_code == 0
          exit_code = 1 if merge_failures_errored && exit_code == 0
          exit_code
        ensure
          if suite_started
            env_after = ENV.to_h.merge(
              "POLYRUN_HOOK_ORCHESTRATOR" => "1",
              "POLYRUN_SHARD_TOTAL" => ctx[:workers].to_s,
              "POLYRUN_SUITE_EXIT_STATUS" => exit_code.to_s,
              "POLYRUN_MERGED_FAILURES_PATH" => merged_failures_path.to_s
            )
            begin
              hook_cfg.run_phase_if_enabled(:after_suite, env_after)
            rescue Interrupt
              Polyrun::Log.warn "polyrun run-shards: after_suite hook interrupted; workers are stopped or were not started"
            end
          end
        end
      end
      # rubocop:enable Metrics/AbcSize

      def run_shards_warn_interleaved(parallel, pid_count)
        return unless parallel && pid_count > 1

        Polyrun::Log.warn "polyrun run-shards: #{pid_count} children running; RSpec output below may be interleaved."
        Polyrun::Log.warn "polyrun run-shards: each worker prints its own summary line; the last \"N examples\" line is not a total across shards."
      end

      def run_shards_merge_or_hint_coverage(ctx)
        if ctx[:merge_coverage]
          mo = ctx[:merge_output] || "coverage/merged.json"
          mf = ctx[:merge_format] || ENV["POLYRUN_MERGE_FORMATS"] || Polyrun::Coverage::Reporting::DEFAULT_MERGE_FORMAT_LIST
          Polyrun::Debug.log("run-shards: starting post-worker merge_coverage_after_shards → #{mo}")
          return merge_coverage_after_shards(output: mo, format_list: mf, config_path: ctx[:config_path])
        end

        if ctx[:parallel]
          Polyrun::Log.warn <<~MSG
            polyrun run-shards: coverage — each worker writes coverage/polyrun-fragment-worker<N>.json when Polyrun coverage is enabled (POLYRUN_SHARD_INDEX per process).
            polyrun run-shards: next step — merge with: polyrun merge-coverage -i 'coverage/polyrun-fragment-*.json' -o coverage/merged.json --format json,cobertura,console
          MSG
        end
        0
      end

      def run_shards_log_failed_reruns(failed, shard_results, plan, parallel, workers, cmd, merge_failures: false)
        exit_by_shard = shard_results.each_with_object({}) { |r, h| h[r[:shard]] = r[:exitstatus] }
        failed_detail = failed.sort.map { |s| "#{s} (exit #{exit_by_shard[s]})" }.join(", ")
        Polyrun::Log.warn "polyrun run-shards: failed shard(s): #{failed_detail}"
        if parallel
          Polyrun::Log.warn "polyrun run-shards: search this log for the failed shard's output, or re-run one shard at a time (below) for a clean RSpec report."
        end
        failed.sort.each do |s|
          paths = plan.shard(s)
          next if paths.empty?

          rerun = "export POLYRUN_SHARD_INDEX=#{s} POLYRUN_SHARD_TOTAL=#{workers}; "
          rerun << Shellwords.join(cmd + paths)
          Polyrun::Log.warn "polyrun run-shards: shard #{s} re-run (same spec list, no interleave): #{rerun}"
        end
        unless merge_failures
          Polyrun::Log.warn "polyrun run-shards: one merged failure report — use run-shards --merge-failures with Polyrun::RSpec.install_failure_fragments!; POLYRUN_MERGED_FAILURES_PATH is set on after_suite when merge runs."
        end
      end
    end
  end
end
