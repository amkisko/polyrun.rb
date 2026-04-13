require "optparse"

module Polyrun
  class CLI
    module EnvCommands
      private

      def cmd_env(argv, config_path)
        shard, total, base_database = env_parse_options!(argv)
        cfg = Polyrun::Config.load(path: config_path || ENV["POLYRUN_CONFIG"])
        pc = cfg.partition
        shard = shard.nil? ? resolve_shard_index(pc) : shard
        total = total.nil? ? resolve_shard_total(pc) : total

        env_print_database_exports(cfg.databases, shard)
        Polyrun::Database::Shard.env_map(shard_index: shard, shard_total: total, base_database: base_database).each do |k, v|
          Polyrun::Log.puts %(export #{k}=#{v})
        end
        0
      end

      def env_parse_options!(argv)
        shard = nil
        total = nil
        base_database = nil
        OptionParser.new do |opts|
          opts.on("--shard INDEX", Integer) { |v| shard = v }
          opts.on("--total N", Integer) { |v| total = v }
          opts.on("--database TEMPLATE", String) { |v| base_database = v }
        end.parse!(argv)
        [shard, total, base_database]
      end

      def env_print_database_exports(dh, shard)
        return unless dh.is_a?(Hash) && !dh.empty?

        Polyrun::Database::UrlBuilder.env_exports_for_databases(dh, shard_index: shard).each do |k, v|
          Polyrun::Log.puts %(export #{k}=#{v})
        end
      end
    end
  end
end
