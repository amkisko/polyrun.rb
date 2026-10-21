module Polyrun
  module Queue
    # Claim / run / ack loop for +polyrun run-queue+ workers (forked or direct).
    #
    # Successful batches stay one command invocation. On failure, paths are re-run one at a time so
    # already-passing paths can be acked without reclaiming them with a poison neighbor.
    module WorkerLoop
      module_function

      def run(store:, worker_id:, batch:, cmd:, on_failure:)
        batches_ok = 0
        batches_fail = 0
        loop do
          claim = store.claim!(worker_id: worker_id, batch_size: batch)
          paths = claim["paths"] || []
          break if paths.empty?

          store.heartbeat!(lease_id: claim["lease_id"], worker_id: worker_id)
          code = run_batch(cmd, paths)
          if code == 0
            store.ack!(lease_id: claim["lease_id"], worker_id: worker_id)
            batches_ok += 1
            next
          end

          outcome = isolate_failed_batch!(
            store: store,
            worker_id: worker_id,
            lease_id: claim["lease_id"],
            paths: paths,
            cmd: cmd,
            on_failure: on_failure
          )
          batches_ok += outcome[:ok]
          batches_fail += outcome[:fail]
          return {ok: batches_ok, fail: batches_fail, exit_code: outcome[:exit_code]} if outcome[:stop]
        end
        {ok: batches_ok, fail: batches_fail, exit_code: 0}
      rescue Polyrun::Error => e
        Polyrun::Log.warn "polyrun run-queue worker #{worker_id}: #{e.message}"
        {ok: batches_ok, fail: batches_fail, exit_code: 2}
      end

      def run_batch(cmd, paths)
        system(*cmd, *paths) ? 0 : ($?.exitstatus || 1)
      end

      def isolate_failed_batch!(store:, worker_id:, lease_id:, paths:, cmd:, on_failure:)
        ok = 0
        paths.each do |path|
          store.heartbeat!(lease_id: lease_id, worker_id: worker_id)
          code = run_batch(cmd, [path])
          if code == 0
            store.ack_paths!(lease_id: lease_id, worker_id: worker_id, paths: [path])
            ok += 1
            next
          end

          if on_failure.to_s == "requeue"
            store.reclaim_lease!(lease_id)
            return {ok: ok, fail: 1, exit_code: 1, stop: true}
          end

          return {ok: ok, fail: 1, exit_code: code.zero? ? 1 : code, stop: true}
        end

        # Every path passed on the isolating re-run; lease should already be empty.
        {ok: ok.positive? ? 1 : 0, fail: 0, exit_code: 0, stop: false}
      end
      private_class_method :isolate_failed_batch!
    end
  end
end
