require_relative "../worker_output"

module Polyrun
  class CLI
    # SIGINT/SIGTERM handling and non-blocking reap for parallel worker PIDs (used by run-shards / ci-shard fan-out).
    module RunShardsWorkerInterrupt
      private

      def run_shards_log_interrupt_workers(pids, _ctx)
        parts = pids.map { |h| "shard=#{h[:shard]} pid=#{h[:pid]}" }
        Polyrun::Log.orchestration_warn "polyrun run-shards: SIGINT/SIGTERM while waiting on workers — stopping: #{parts.join(", ")}"
        if Polyrun::WorkerOutput.routing_enabled?
          Polyrun::Log.warn "polyrun run-shards: per-shard worker logs under #{Polyrun::WorkerOutput.worker_log_directory_label}"
        else
          Polyrun::Log.warn "polyrun run-shards: search this log for each shard's started … pid= line and RSpec output; repeat SIGINT during cleanup escalates to SIGKILL"
        end
      end

      # Best-effort worker teardown then exit. Does not return.
      def run_shards_shutdown_on_signal!(pids, code)
        run_shards_log_interrupt_workers(pids, nil)
        run_shards_terminate_children!(pids)
        exit(code)
      rescue Interrupt
        run_shards_signal_workers_kill(pids)
        run_shards_reap_worker_pids_interruptible(pids.map { |h| h[:pid] })
        Polyrun::WorkerOutput.shutdown_all!
        exit(code)
      end

      # Signal workers first so pipe readers see EOF; join forwarders only after children exit.
      def run_shards_terminate_children!(pids)
        run_shards_signal_workers_term(pids)
        run_shards_reap_worker_pids_interruptible(pids.map { |h| h[:pid] })
        Polyrun::WorkerOutput.shutdown_all!
      end

      def run_shards_signal_workers_term(pids)
        pids.each { |h| run_shards_kill_process_group!(:TERM, h[:pid]) }
      end

      def run_shards_signal_workers_kill(pids)
        pids.each { |h| run_shards_kill_process_group!(:KILL, h[:pid]) }
      end

      # Negative PID signals the process group (workers spawn with +pgroup: true+).
      def run_shards_kill_process_group!(signal, pid)
        Process.kill(signal, -Integer(pid))
      rescue Errno::ESRCH, Errno::EPERM
        begin
          Process.kill(signal, Integer(pid))
        rescue Errno::ESRCH, Errno::EPERM
          nil
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
            pending.each { |pid| run_shards_kill_process_group!(:KILL, pid) }
          end
        end
      end
    end
  end
end
