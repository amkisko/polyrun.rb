module Polyrun
  module Queue
    # Claim / run / ack loop for +polyrun run-queue+ workers (forked or direct).
    module WorkerLoop
      module_function

      def run(store:, worker_id:, batch:, cmd:, on_failure:)
        batches_ok = 0
        batches_fail = 0
        loop do
          claim = store.claim!(worker_id: worker_id, batch_size: batch)
          paths = claim["paths"] || []
          break if paths.empty?

          code = run_batch(cmd, paths)
          if code == 0
            store.ack!(lease_id: claim["lease_id"], worker_id: worker_id)
            batches_ok += 1
          elsif on_failure.to_s == "requeue"
            store.reclaim_lease!(claim["lease_id"])
            batches_fail += 1
            return {ok: batches_ok, fail: batches_fail, exit_code: 1}
          else
            batches_fail += 1
            return {ok: batches_ok, fail: batches_fail, exit_code: code.zero? ? 1 : code}
          end
        end
        {ok: batches_ok, fail: batches_fail, exit_code: 0}
      rescue Polyrun::Error => e
        Polyrun::Log.warn "polyrun run-queue worker #{worker_id}: #{e.message}"
        {ok: batches_ok, fail: batches_fail, exit_code: 2}
      end

      def run_batch(cmd, paths)
        system(*cmd, *paths) ? 0 : ($?.exitstatus || 1)
      end
    end
  end
end
