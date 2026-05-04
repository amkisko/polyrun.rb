# rubocop:disable Polyrun/FileLength, Metrics/ModuleLength -- wait loop + idle/wall flush (kept out of spawn module)
module Polyrun
  class CLI
    # Wait, wall/idle timeout, and +after_shard+ hooks for parallel workers (+run-shards+ / +ci-shard-*+).
    module RunShardsParallelWait
      WORKER_TIMEOUT_EXIT_STATUS = 124
      WORKER_IDLE_TIMEOUT_EXIT_STATUS = 125

      private

      # @return [Array(Array, Integer)] +[shard_results, after_shard_hook_error_code]+ (0 when all +after_shard+ hooks passed)
      # rubocop:disable Metrics/AbcSize -- wait loop + timeout flush
      def run_shards_wait_all_children(pids, hook_cfg, ctx)
        workers = ctx[:workers]
        shard_results = []
        after_hook_err = 0
        timeout_sec = ctx[:worker_timeout_sec]
        timeout_sec = nil if timeout_sec.is_a?(Numeric) && timeout_sec <= 0
        idle_sec = ctx[:worker_idle_timeout_sec]
        idle_sec = nil if idle_sec.is_a?(Numeric) && idle_sec <= 0

        Polyrun::Debug.time("Process.wait (#{pids.size} worker process(es))") do
          if timeout_sec || idle_sec
            run_shards_wait_all_children_multiplex(
              pids, hook_cfg, ctx, workers, timeout_sec, idle_sec, shard_results, after_hook_err
            )
          else
            run_shards_wait_all_children_sequential(pids, hook_cfg, workers, shard_results, after_hook_err)
          end
        rescue Interrupt
          run_shards_shutdown_on_signal!(pids, 130)
        rescue SignalException => e
          raise unless e.signm == "SIGTERM"

          run_shards_shutdown_on_signal!(pids, 143)
        end
      end
      # rubocop:enable Metrics/AbcSize

      def run_shards_wait_all_children_sequential(pids, hook_cfg, workers, shard_results, after_hook_err)
        pids.each do |h|
          Process.wait(h[:pid])
          st = $?
          after_hook_err = run_shards_finalize_reaped_worker!(h, hook_cfg, workers, st, shard_results, after_hook_err)
        end
        [shard_results, after_hook_err]
      end

      # Poll every live PID each tick so wall and idle timeouts apply to all workers, not only the first in wait order.
      def run_shards_wait_all_children_multiplex(pids, hook_cfg, ctx, workers, timeout_sec, idle_sec, shard_results, after_hook_err)
        pending = pids.dup

        loop do
          pending.delete_if do |h|
            wpid = Process.wait(h[:pid], Process::WNOHANG)
            next false unless wpid == h[:pid]

            st = $?
            after_hook_err = run_shards_finalize_reaped_worker!(h, hook_cfg, workers, st, shard_results, after_hook_err)
            true
          end

          return [shard_results, after_hook_err] if pending.empty?

          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          violation = run_shards_timeout_violation(pids, pending, ctx, now, timeout_sec, idle_sec)
          if violation
            reason, timed_h = violation
            others = pending.reject { |x| x[:pid] == timed_h[:pid] }
            case reason
            when :wall_timeout
              return run_shards_wait_flush_after_worker_timeout!(
                timed_h, others, hook_cfg, ctx, timeout_sec, workers, shard_results, after_hook_err
              )
            when :idle_timeout
              return run_shards_wait_flush_after_worker_idle!(
                timed_h, others, hook_cfg, ctx, idle_sec, workers, shard_results, after_hook_err
              )
            end
          end

          sleep(0.2)
        end
      end

      # @return [(Symbol, Hash), nil] e.g. +[:wall_timeout, h]+ when a limit is exceeded
      def run_shards_timeout_violation(pids_order, pending, ctx, now, timeout_sec, idle_sec)
        pids_order.each do |h|
          next unless pending.any? { |p| p[:pid] == h[:pid] }

          if timeout_sec && timeout_sec > 0
            spawned_at = h[:spawned_at] || ctx[:run_t0]
            return [:wall_timeout, h] if now >= spawned_at + timeout_sec
          end
        end

        pids_order.each do |h|
          next unless pending.any? { |p| p[:pid] == h[:pid] }

          next unless idle_sec && idle_sec > 0 && h[:ping_path]

          t, = run_shards_read_worker_ping_payload(h[:ping_path])
          return [:idle_timeout, h] if t && (now - t) > idle_sec
        end

        nil
      end

      def run_shards_finalize_reaped_worker!(h, hook_cfg, workers, st, shard_results, after_hook_err)
        exitstatus = st.exitstatus
        ok = st.success?
        Polyrun::Debug.log("[parent pid=#{$$}] run-shards: Process.wait child_pid=#{h[:pid]} shard=#{h[:shard]} exit=#{exitstatus} success=#{ok}")
        rc = run_shards_invoke_after_shard!(hook_cfg, h[:shard], workers, exitstatus)
        after_hook_err = rc if rc != 0 && after_hook_err == 0
        shard_results << {shard: h[:shard], exitstatus: exitstatus, success: ok}
        run_shards_unlink_ping_path(h[:ping_path])
        after_hook_err
      end

      def run_shards_unlink_ping_path(path)
        s = path.to_s.strip
        return if s.empty?

        File.unlink(s) if File.file?(s)
      rescue SystemCallError
        # best-effort cleanup of tmp/polyrun/worker-ping-*.txt
      end

      def run_shards_read_worker_ping_time(path)
        run_shards_read_worker_ping_payload(path)[0]
      end

      # @return [Array(Float?, String?)] monotonic time and optional location line (path:line)
      def run_shards_read_worker_ping_payload(path)
        return [nil, nil] unless path && File.file?(path)

        s = File.binread(path)
        return [nil, nil] if s.nil? || s.strip.empty?

        time_line, rest = s.split("\n", 2)
        first = time_line.to_s.strip
        return [nil, nil] if first.empty?

        f = first.to_f
        t = f.positive? ? f : nil
        loc = rest.to_s.strip
        loc = nil if loc.empty?
        [t, loc]
      rescue SystemCallError
        [nil, nil]
      end

      def run_shards_wait_flush_after_worker_idle!(timed_h, others, hook_cfg, ctx, idle_sec, workers, shard_results, after_hook_err)
        run_shards_warn_worker_idle!(timed_h, ctx, idle_sec)
        run_shards_force_stop_pid_status(timed_h[:pid])
        run_shards_unlink_ping_path(timed_h[:ping_path])
        rc = run_shards_invoke_after_shard!(hook_cfg, timed_h[:shard], workers, WORKER_IDLE_TIMEOUT_EXIT_STATUS)
        after_hook_err = rc if rc != 0 && after_hook_err == 0
        shard_results << {shard: timed_h[:shard], exitstatus: WORKER_IDLE_TIMEOUT_EXIT_STATUS, success: false}
        others.each do |h2|
          st2 = run_shards_wait_or_force_stop_status(h2[:pid])
          exit2 = st2&.exitstatus
          ok2 = st2 ? st2.success? : false
          exit2 = WORKER_IDLE_TIMEOUT_EXIT_STATUS if exit2.nil?
          run_shards_unlink_ping_path(h2[:ping_path])
          rc2 = run_shards_invoke_after_shard!(hook_cfg, h2[:shard], workers, exit2)
          after_hook_err = rc2 if rc2 != 0 && after_hook_err == 0
          shard_results << {shard: h2[:shard], exitstatus: exit2, success: ok2}
        end
        [shard_results, after_hook_err]
      end

      def run_shards_wait_flush_after_worker_timeout!(timed_h, others, hook_cfg, ctx, timeout_sec, workers, shard_results, after_hook_err)
        run_shards_warn_worker_timeout!(timed_h, ctx, timeout_sec)
        run_shards_force_stop_pid_status(timed_h[:pid])
        run_shards_unlink_ping_path(timed_h[:ping_path])
        rc = run_shards_invoke_after_shard!(hook_cfg, timed_h[:shard], workers, WORKER_TIMEOUT_EXIT_STATUS)
        after_hook_err = rc if rc != 0 && after_hook_err == 0
        shard_results << {shard: timed_h[:shard], exitstatus: WORKER_TIMEOUT_EXIT_STATUS, success: false}
        others.each do |h2|
          st2 = run_shards_wait_or_force_stop_status(h2[:pid])
          exit2 = st2&.exitstatus
          ok2 = st2 ? st2.success? : false
          exit2 = WORKER_TIMEOUT_EXIT_STATUS if exit2.nil?
          run_shards_unlink_ping_path(h2[:ping_path])
          rc2 = run_shards_invoke_after_shard!(hook_cfg, h2[:shard], workers, exit2)
          after_hook_err = rc2 if rc2 != 0 && after_hook_err == 0
          shard_results << {shard: h2[:shard], exitstatus: exit2, success: ok2}
        end
        [shard_results, after_hook_err]
      end

      def run_shards_invoke_after_shard!(hook_cfg, shard, workers, exitstatus)
        env_after = ENV.to_h.merge(
          "POLYRUN_HOOK_ORCHESTRATOR" => "1",
          "POLYRUN_SHARD_INDEX" => shard.to_s,
          "POLYRUN_SHARD_TOTAL" => workers.to_s,
          "POLYRUN_WORKER_EXIT_STATUS" => exitstatus.to_s
        )
        hook_cfg.run_phase_if_enabled(:after_shard, env_after)
      end

      def run_shards_warn_worker_idle!(h, ctx, idle_sec)
        paths = ctx[:plan].shard(h[:shard])
        sample = paths.first(5).join(", ")
        suffix =
          if paths.empty?
            " (no paths)"
          elsif paths.size > 5
            " (#{paths.size} files total)"
          else
            ""
          end
        _t, loc = run_shards_read_worker_ping_payload(h[:ping_path])
        ping_suffix = (loc && !loc.to_s.strip.empty?) ? "; last ping #{loc.to_s.strip}" : ""
        Polyrun::Log.orchestration_warn "polyrun run-shards: WORKER IDLE TIMEOUT after #{idle_sec}s since last per-example progress ping — shard #{h[:shard]} pid #{h[:pid]}#{ping_suffix}."
        Polyrun::Log.warn "polyrun run-shards: idle shard file sample: #{sample}#{suffix}"
        Polyrun::Log.warn "polyrun run-shards: use Polyrun::RSpec.install_worker_ping! / Polyrun::Minitest.install_worker_ping! (Polyrun Quick calls ping! each example); exit #{WORKER_IDLE_TIMEOUT_EXIT_STATUS}."
      end

      def run_shards_wait_or_force_stop_status(pid)
        wpid = Process.wait(pid, Process::WNOHANG)
        return $? if wpid == pid

        run_shards_force_stop_pid_status(pid)
      rescue Errno::ECHILD
        nil
      end

      def run_shards_force_stop_pid_status(pid)
        Process.kill(:KILL, pid)
        st = nil
        begin
          Process.wait(pid)
          st = $?
        rescue Errno::ECHILD
          # child already reaped
        end
        st
      rescue Errno::ESRCH
        begin
          Process.wait(pid)
          $?
        rescue Errno::ECHILD
          nil
        end
      end

      def run_shards_warn_worker_timeout!(h, ctx, timeout_sec)
        paths = ctx[:plan].shard(h[:shard])
        sample = paths.first(5).join(", ")
        suffix =
          if paths.empty?
            " (no paths)"
          elsif paths.size > 5
            " (#{paths.size} files total)"
          else
            ""
          end
        Polyrun::Log.orchestration_warn "polyrun run-shards: WORKER TIMEOUT after #{timeout_sec}s (wall time since worker spawn) — shard #{h[:shard]} pid #{h[:pid]}."
        Polyrun::Log.warn "polyrun run-shards: timeout shard includes: #{sample}#{suffix}"
        Polyrun::Log.warn "polyrun run-shards: override with --worker-timeout SEC or POLYRUN_WORKER_TIMEOUT_SEC; recorded exit #{WORKER_TIMEOUT_EXIT_STATUS} for this worker."
      end
    end
  end
end
# rubocop:enable Polyrun/FileLength, Metrics/ModuleLength
