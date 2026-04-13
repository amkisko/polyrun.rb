require "optparse"

module Polyrun
  class CLI
    module EnvCommands
      private

      def cmd_env(argv, config_path)
        shard = nil
        total = nil
        base_database = nil
        parser = OptionParser.new do |opts|
          opts.on("--shard INDEX", Integer) { |v| shard = v }
          opts.on("--total N", Integer) { |v| total = v }
          opts.on("--database TEMPLATE", String) { |v| base_database = v }
        end
        parser.parse!(argv)

        cfg = Polyrun::Config.load(path: config_path || ENV["POLYRUN_CONFIG"])
        pc = cfg.partition
        shard = shard.nil? ? resolve_shard_index(pc) : shard
        total = total.nil? ? resolve_shard_total(pc) : total

        dh = cfg.databases
        if dh.is_a?(Hash) && !dh.empty?
          Polyrun::Database::UrlBuilder.env_exports_for_databases(dh, shard_index: shard).each do |k, v|
            Polyrun::Log.puts %(export #{k}=#{v})
          end
        end

        Polyrun::Database::Shard.env_map(shard_index: shard, shard_total: total, base_database: base_database).each do |k, v|
          Polyrun::Log.puts %(export #{k}=#{v})
        end
        0
      end
    end
  end
end
