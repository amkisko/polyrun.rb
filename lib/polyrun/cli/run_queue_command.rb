require "json"
require "optparse"
require "shellwords"

require_relative "../queue/duration"

module Polyrun
  class CLI
    module RunQueueCommand
      private

      # rubocop:disable Metrics/AbcSize -- queue worker argv + spawn loop
      def cmd_run_queue(argv, config_path)
        dir = ".polyrun-queue"
        batch = 5
        on_failure = "exit"
        paths_file = nil
        workers = nil

        sep = argv.index("--")
        unless sep
          Polyrun::Log.warn "polyrun run-queue: need -- before the command"
          return 2
        end

        head = argv[0...sep]
        cmd = argv[(sep + 1)..].map(&:to_s)
        return 2 if cmd.empty?

        cfg = Polyrun::Config.load(path: config_path || ENV["POLYRUN_CONFIG"])
        pc = cfg.partition
        ctx = plan_command_initial_context(pc)

        OptionParser.new do |opts|
          opts.banner = "usage: polyrun run-queue [--workers N] [--batch N] [--dir DIR] [--on-failure exit|requeue] [partition options] -- <command>"
          opts.on("--workers N", Integer) { |v| workers = v }
          opts.on("--batch N", Integer) { |v| batch = v }
          opts.on("--dir PATH") { |v| dir = v }
          opts.on("--paths-file PATH", String) { |v| paths_file = v }
          opts.on("--on-failure MODE", "exit (default) or requeue") { |v| on_failure = v }
          plan_command_register_partition_options!(opts, ctx)
        end.parse!(head)

        workers ||= env_int("POLYRUN_WORKERS", Polyrun::Config::DEFAULT_PARALLEL_WORKERS)
        paths_file ||= pc["paths_file"] || pc[:paths_file]
        unless paths_file
          Polyrun::Log.warn "polyrun run-queue: need --paths-file or partition.paths_file"
          return 2
        end

        code = Polyrun::Partition::PathsBuild.apply!(partition: pc, cwd: Dir.pwd)
        return code if code != 0

        store = Polyrun::Queue::FileStore.new(dir)
        if File.file?(File.join(File.expand_path(dir), "queue.json"))
          Polyrun::Log.warn "polyrun run-queue: queue already exists at #{dir}; remove it or use --dir"
          return 2
        end

        ordered, code = queue_partition_manifest_and_ordered_paths(cfg, pc, ctx, paths_file)
        return code if code != 0

        store.init!(ordered)
        Polyrun::Log.warn "polyrun run-queue: #{ordered.size} path(s), #{workers} worker(s), batch=#{batch}" if @verbose

        run_t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        pids = run_queue_spawn_workers(store: store, workers: workers, batch: batch, cmd: cmd, on_failure: on_failure)
        results = run_queue_wait_workers(pids, store: store, on_failure: on_failure)
        wall = Process.clock_gettime(Process::CLOCK_MONOTONIC) - run_t0

        stat = store.status(detailed: true)
        Polyrun::Log.warn format(
          "polyrun run-queue: done pending=%d done=%d leases=%d wall=%.1fs batches_ok=%d batches_fail=%d",
          stat["pending"], stat["done"], stat["leases"], wall, results[:ok], results[:fail]
        )

        results[:fail].positive? ? 1 : 0
      end
      # rubocop:enable Metrics/AbcSize

      def run_queue_spawn_workers(store:, workers:, batch:, cmd:, on_failure:)
        pids = []
        workers.times do |i|
          wid = "worker-#{i}"
          pid = Process.fork do
            run_queue_worker_loop(store: store, worker_id: wid, batch: batch, cmd: cmd, on_failure: on_failure)
          end
          pids << {pid: pid, worker_id: wid}
        end
        pids
      end

      def run_queue_worker_loop(store:, worker_id:, batch:, cmd:, on_failure:)
        batches_ok = 0
        batches_fail = 0
        loop do
          claim = store.claim!(worker_id: worker_id, batch_size: batch)
          paths = claim["paths"] || []
          break if paths.empty?

          code = run_queue_run_batch(cmd, paths)
          if code == 0
            store.ack!(lease_id: claim["lease_id"], worker_id: worker_id)
            batches_ok += 1
          elsif on_failure.to_s == "requeue"
            store.reclaim_lease!(claim["lease_id"])
            batches_fail += 1
            exit 1
          else
            batches_fail += 1
            exit code.zero? ? 1 : code
          end
        end
        exit 0
      rescue Polyrun::Error => e
        Polyrun::Log.warn "polyrun run-queue worker #{worker_id}: #{e.message}"
        exit 2
      end

      def run_queue_run_batch(cmd, paths)
        system(*cmd, *paths) ? 0 : ($?.exitstatus || 1)
      end

      def run_queue_wait_workers(pids, store:, on_failure:)
        ok = 0
        fail = 0
        pid_to_worker = pids.each_with_object({}) { |entry, h| h[entry[:pid]] = entry[:worker_id] }
        while pid_to_worker.any?
          pid, st = Process.wait2(-1)
          worker_id = pid_to_worker.delete(pid)
          next unless worker_id

          if st.success?
            ok += 1
          else
            fail += 1
            reclaimed = store.reclaim!(worker_id: worker_id)
            Polyrun::Log.warn "polyrun run-queue: reclaimed #{reclaimed} path(s) from #{worker_id}" if reclaimed.positive?
          end
        end
        {ok: ok, fail: fail}
      end
    end
  end
end
