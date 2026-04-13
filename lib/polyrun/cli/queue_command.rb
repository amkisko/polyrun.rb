require "json"
require "optparse"

module Polyrun
  class CLI
    module QueueCommand
      private

      # File-backed queue (spec_queue.md): init → claim batches → ack (ledger append-only).
      def cmd_queue(argv)
        dir = ".polyrun-queue"
        paths_file = nil
        timing_path = nil
        worker = ENV["USER"] || "worker"
        batch = 5
        lease_id = nil

        sub = argv.shift
        Polyrun::Debug.log("queue: subcommand=#{sub.inspect}")
        case sub
        when "init"
          parser = OptionParser.new do |opts|
            opts.banner = "usage: polyrun queue init --paths-file P [--timing PATH] [--dir DIR]"
            opts.on("--dir PATH") { |v| dir = v }
            opts.on("--paths-file PATH") { |v| paths_file = v }
            opts.on("--timing PATH") { |v| timing_path = v }
          end
          parser.parse!(argv)
          unless paths_file
            Polyrun::Log.warn "queue init: need --paths-file"
            return 2
          end
          items = Polyrun::Partition::Paths.read_lines(paths_file)
          costs = timing_path ? Polyrun::Partition::Plan.load_timing_costs(File.expand_path(timing_path, Dir.pwd)) : nil
          ordered =
            if costs && !costs.empty?
              dw = costs.values.sum / costs.size.to_f
              items.sort_by { |p| [-queue_weight_for(p, costs, dw), p] }
            else
              items.sort
            end
          Polyrun::Queue::FileStore.new(dir).init!(ordered)
          Polyrun::Log.puts JSON.generate({"dir" => File.expand_path(dir), "count" => ordered.size})
          0
        when "claim"
          parser = OptionParser.new do |opts|
            opts.banner = "usage: polyrun queue claim [--dir DIR] [--worker ID] [--batch N]"
            opts.on("--dir PATH") { |v| dir = v }
            opts.on("--worker ID") { |v| worker = v }
            opts.on("--batch N", Integer) { |v| batch = v }
          end
          parser.parse!(argv)
          r = Polyrun::Queue::FileStore.new(dir).claim!(worker_id: worker, batch_size: batch)
          Polyrun::Log.puts JSON.generate(r)
          0
        when "ack"
          parser = OptionParser.new do |opts|
            opts.banner = "usage: polyrun queue ack --lease ID [--dir DIR] [--worker ID]"
            opts.on("--dir PATH") { |v| dir = v }
            opts.on("--lease ID") { |v| lease_id = v }
            opts.on("--worker ID") { |v| worker = v }
          end
          parser.parse!(argv)
          unless lease_id
            Polyrun::Log.warn "queue ack: need --lease"
            return 2
          end
          Polyrun::Queue::FileStore.new(dir).ack!(lease_id: lease_id, worker_id: worker)
          Polyrun::Log.puts "ok"
          0
        when "status"
          parser = OptionParser.new do |opts|
            opts.on("--dir PATH") { |v| dir = v }
          end
          parser.parse!(argv)
          s = Polyrun::Queue::FileStore.new(dir).status
          Polyrun::Log.puts JSON.generate(s)
          0
        else
          Polyrun::Log.warn "usage: polyrun queue {init|claim|ack|status} [options]"
          2
        end
      end
    end
  end
end
