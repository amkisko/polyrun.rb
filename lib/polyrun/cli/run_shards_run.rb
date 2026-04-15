require "shellwords"
require "rbconfig"

require_relative "run_shards_planning"

module Polyrun
  class CLI
    # Partition + spawn workers for `polyrun run-shards` (keeps {RunShardsCommand} file small).
    module RunShardsRun
      include RunShardsPlanning

      private

      def run_shards_run!(argv, config_path)
        code, ctx = run_shards_build_plan(argv, config_path)
        return code if code

        run_shards_workers_and_merge(ctx)
      end

      def run_shards_workers_and_merge(ctx)
        pids = run_shards_spawn_workers(ctx)
        return 1 if pids.empty?

        run_shards_warn_interleaved(ctx[:parallel], pids.size)

        shard_results = run_shards_wait_all_children(pids)
        failed = shard_results.reject { |r| r[:success] }.map { |r| r[:shard] }

        Polyrun::Debug.log(format(
          "run-shards: workers wall time since start: %.3fs",
          Process.clock_gettime(Process::CLOCK_MONOTONIC) - ctx[:run_t0]
        ))

        if ctx[:parallel]
          Polyrun::Log.warn "polyrun run-shards: finished #{pids.size} worker(s)" + (failed.any? ? " (some failed)" : " (exit 0)")
        end

        if failed.any?
          run_shards_log_failed_reruns(failed, shard_results, ctx[:plan], ctx[:parallel], ctx[:workers], ctx[:cmd])
          return 1
        end

        run_shards_merge_or_hint_coverage(ctx)
      end

      def run_shards_spawn_workers(ctx)
        workers = ctx[:workers]
        cmd = ctx[:cmd]
        cfg = ctx[:cfg]
        plan = ctx[:plan]
        parallel = ctx[:parallel]
        mx = ctx[:matrix_shard_index]
        mt = ctx[:matrix_shard_total]

        pids = []
        workers.times do |shard|
          paths = plan.shard(shard)
          if paths.empty?
            Polyrun::Log.warn "polyrun run-shards: shard #{shard} skipped (no paths)" if @verbose || parallel
            next
          end

          child_env = shard_child_env(cfg: cfg, workers: workers, shard: shard, matrix_index: mx, matrix_total: mt)

          Polyrun::Log.warn "polyrun run-shards: shard #{shard} → #{paths.size} file(s)" if @verbose
          pid = Process.spawn(child_env, *cmd, *paths)
          pids << {pid: pid, shard: shard}
          Polyrun::Debug.log("[parent pid=#{$$}] run-shards: Process.spawn shard=#{shard} child_pid=#{pid} spec_files=#{paths.size}")
          Polyrun::Log.warn "polyrun run-shards: started shard #{shard} pid=#{pid} (#{paths.size} file(s))" if parallel
        end
        pids
      end

      def run_shards_warn_interleaved(parallel, pid_count)
        return unless parallel && pid_count > 1

        Polyrun::Log.warn "polyrun run-shards: #{pid_count} children running; RSpec output below may be interleaved."
        Polyrun::Log.warn "polyrun run-shards: each worker prints its own summary line; the last \"N examples\" line is not a total across shards."
      end

      def run_shards_wait_all_children(pids)
        shard_results = []
        Polyrun::Debug.time("Process.wait (#{pids.size} worker process(es))") do
          pids.each do |h|
            Process.wait(h[:pid])
            exitstatus = $?.exitstatus
            ok = $?.success?
            Polyrun::Debug.log("[parent pid=#{$$}] run-shards: Process.wait child_pid=#{h[:pid]} shard=#{h[:shard]} exit=#{exitstatus} success=#{ok}")
            shard_results << {shard: h[:shard], exitstatus: exitstatus, success: ok}
          end
        rescue Interrupt
          # Do not trap SIGINT: Process.wait raises Interrupt; a trap races and prints Interrupt + SystemExit traces.
          run_shards_shutdown_on_signal!(pids, 130)
        rescue SignalException => e
          raise unless e.signm == "SIGTERM"

          run_shards_shutdown_on_signal!(pids, 143)
        end
        shard_results
      end

      # Best-effort worker teardown then exit. Does not return.
      def run_shards_shutdown_on_signal!(pids, code)
        run_shards_terminate_children!(pids)
        exit(code)
      rescue Interrupt
        pids.each do |h|
          Process.kill(:KILL, h[:pid])
        rescue Errno::ESRCH
          # already reaped
        end
        pids.each do |h|
          Process.wait(h[:pid])
        rescue Errno::ESRCH, Errno::ECHILD, Interrupt
          # already reaped or give up
        end
        exit(code)
      end

      # Send SIGTERM to each worker PID and wait so Ctrl+C / SIGTERM does not leave orphans.
      def run_shards_terminate_children!(pids)
        pids.each do |h|
          Process.kill(:TERM, h[:pid])
        rescue Errno::ESRCH
          # already reaped
        end
        pids.each do |h|
          Process.wait(h[:pid])
        rescue Errno::ESRCH, Errno::ECHILD
          # already reaped
        end
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

      def run_shards_log_failed_reruns(failed, shard_results, plan, parallel, workers, cmd)
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
      end
    end
  end
end
