module Polyrun
  class CLI
    # SIGINT/SIGTERM handling and non-blocking reap for parallel worker PIDs (used by run-shards / ci-shard fan-out).
    module RunShardsWorkerInterrupt
      private

      def run_shards_log_interrupt_workers(pids, _ctx)
        parts = pids.map { |h| "shard=#{h[:shard]} pid=#{h[:pid]}" }
        Polyrun::Log.orchestration_warn "polyrun run-shards: SIGINT/SIGTERM while waiting on workers — stopping: #{parts.join(", ")}"
        Polyrun::Log.warn "polyrun run-shards: search this log for each shard's started … pid= line and RSpec output; repeat SIGINT during cleanup escalates to SIGKILL"
      end

      # Best-effort worker teardown then exit. Does not return.
      def run_shards_shutdown_on_signal!(pids, code)
        run_shards_log_interrupt_workers(pids, nil)
        run_shards_terminate_children!(pids)
        exit(code)
      rescue Interrupt
        run_shards_signal_workers_kill(pids)
        run_shards_reap_worker_pids_interruptible(pids.map { |h| h[:pid] })
        exit(code)
      end

      # Send SIGTERM to each worker PID and wait so Ctrl+C / SIGTERM does not leave orphans.
      def run_shards_terminate_children!(pids)
        run_shards_signal_workers_term(pids)
        run_shards_reap_worker_pids_interruptible(pids.map { |h| h[:pid] })
      end

      def run_shards_signal_workers_term(pids)
        pids.each do |h|
          Process.kill(:TERM, h[:pid])
        rescue Errno::ESRCH
        end
      end

      def run_shards_signal_workers_kill(pids)
        pids.each do |h|
          Process.kill(:KILL, h[:pid])
        rescue Errno::ESRCH
        end
      end

      # Reap child PIDs without blocking uninterruptibly on one stuck zombie (avoids noisy stacks on repeat Ctrl+C).
      def run_shards_reap_worker_pids_interruptible(pids)
        pending = pids.compact.uniq
        force_note = false
        until pending.empty?
          pending.reject! do |pid|
            w = Process.wait(pid, Process::WNOHANG)
            next true if w == pid

            false
          rescue Errno::ECHILD
            true
          end
          break if pending.empty?

          begin
            sleep(0.05)
          rescue Interrupt
            unless force_note
              force_note = true
              Polyrun::Log.orchestration_warn "polyrun run-shards: repeated SIGINT during worker cleanup — SIGKILL to #{pending.size} process(es)"
            end
            pending.each do |pid|
              Process.kill(:KILL, pid)
            rescue Errno::ESRCH
            end
          end
        end
      end
    end
  end
end
