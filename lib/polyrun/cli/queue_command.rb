require "json"
require "optparse"

module Polyrun
  class CLI
    module QueueCommand
      private

      # File-backed queue (spec_queue.md): init → claim batches → ack (ledger append-only).
      #
      # *N×M and load balancing*: +queue init+ uses the same +Partition::Plan+ slice as +polyrun plan+
      # when +--shard+ / +--total+ (or +partition.shard_index+ / +shard_total+ / CI env) define a matrix.
      # Each CI job runs +init+ once for its shard; the queue holds **only** that shard's paths (no duplicate
      # work across matrix jobs). **M** local workers use +queue claim+ on a **shared** queue directory
      # (NFS or the runner disk): claims are mutually exclusive — **dynamic** balance (fast workers pull more
      # batches), **not** the same static per-worker wall time as +cost_binpack+ on the full suite.
      # +--timing+ on init sorts dequeue order (heavy items first when weights are known); it does **not**
      # replace binpack across workers — for that, use static +plan+ / +run-shards+ with +cost_binpack+.
      def cmd_queue(argv)
        dir = ".polyrun-queue"
        paths_file = nil
        worker = ENV["USER"] || "worker"
        batch = 5
        lease_id = nil

        sub = argv.shift
        Polyrun::Debug.log("queue: subcommand=#{sub.inspect}")
        case sub
        when "init"
          queue_cmd_init(argv, dir)
        when "claim"
          queue_cmd_claim(argv, dir, worker, batch)
        when "ack"
          queue_cmd_ack(argv, dir, lease_id, worker)
        when "status"
          queue_cmd_status(argv, dir)
        else
          Polyrun::Log.warn "usage: polyrun queue {init|claim|ack|status} [options]"
          2
        end
      end

      def queue_cmd_init(argv, dir)
        cfg = Polyrun::Config.load(path: ENV["POLYRUN_CONFIG"])
        pc = cfg.partition
        ctx = plan_command_initial_context(pc)
        paths_file = nil
        OptionParser.new do |opts|
          opts.banner = "usage: polyrun queue init --paths-file P [--dir DIR] [same partition options as polyrun plan]"
          opts.on("--dir PATH") { |v| dir = v }
          opts.on("--paths-file PATH", String) { |v| paths_file = v }
          plan_command_register_partition_options!(opts, ctx)
        end.parse!(argv)
        unless paths_file
          Polyrun::Log.warn "queue init: need --paths-file"
          return 2
        end
        code = Polyrun::Partition::PathsBuild.apply!(partition: pc, cwd: Dir.pwd)
        return code if code != 0

        ordered, code = queue_partition_manifest_and_ordered_paths(cfg, pc, ctx, paths_file)
        return code if code != 0

        Polyrun::Queue::FileStore.new(dir).init!(ordered)
        Polyrun::Log.puts JSON.generate({"dir" => File.expand_path(dir), "count" => ordered.size})
        0
      end

      def queue_partition_manifest_and_ordered_paths(cfg, pc, ctx, paths_file)
        Polyrun::Log.warn "polyrun queue init: using #{cfg.path}" if @verbose && cfg.path

        manifest, code = plan_command_manifest_from_paths(cfg, pc, [], ctx, paths_file)
        return [nil, code] if code != 0

        paths = manifest["paths"] || []
        g = resolve_partition_timing_granularity(pc, ctx[:timing_granularity])
        timing_for_sort = plan_resolve_timing_path(pc, ctx[:timing_path], ctx[:strategy])
        costs = queue_init_timing_costs(timing_for_sort, g)
        [queue_init_ordered_items(paths, costs, g), 0]
      end

      def queue_init_timing_costs(timing_for_sort, g)
        return nil unless timing_for_sort

        Polyrun::Partition::Plan.load_timing_costs(
          File.expand_path(timing_for_sort.to_s, Dir.pwd),
          granularity: g
        )
      end

      def queue_init_ordered_items(items, costs, granularity = :file)
        if costs && !costs.empty?
          dw = costs.values.sum / costs.size.to_f
          items.sort_by { |p| [-queue_weight_for(p, costs, dw, granularity: granularity), p] }
        else
          items.sort
        end
      end

      def queue_cmd_claim(argv, dir, worker, batch)
        OptionParser.new do |opts|
          opts.banner = "usage: polyrun queue claim [--dir DIR] [--worker ID] [--batch N]"
          opts.on("--dir PATH") { |v| dir = v }
          opts.on("--worker ID") { |v| worker = v }
          opts.on("--batch N", Integer) { |v| batch = v }
        end.parse!(argv)
        r = Polyrun::Queue::FileStore.new(dir).claim!(worker_id: worker, batch_size: batch)
        Polyrun::Log.puts JSON.generate(r)
        0
      end

      def queue_cmd_ack(argv, dir, lease_id, worker)
        OptionParser.new do |opts|
          opts.banner = "usage: polyrun queue ack --lease ID [--dir DIR] [--worker ID]"
          opts.on("--dir PATH") { |v| dir = v }
          opts.on("--lease ID") { |v| lease_id = v }
          opts.on("--worker ID") { |v| worker = v }
        end.parse!(argv)
        unless lease_id
          Polyrun::Log.warn "queue ack: need --lease"
          return 2
        end
        Polyrun::Queue::FileStore.new(dir).ack!(lease_id: lease_id, worker_id: worker)
        Polyrun::Log.puts "ok"
        0
      end

      def queue_cmd_status(argv, dir)
        OptionParser.new do |opts|
          opts.on("--dir PATH") { |v| dir = v }
        end.parse!(argv)
        s = Polyrun::Queue::FileStore.new(dir).status
        Polyrun::Log.puts JSON.generate(s)
        0
      end
    end
  end
end
