require "json"

require_relative "../config/effective"

module Polyrun
  class CLI
    module ConfigCommand
      private

      def cmd_config(argv, config_path)
        dotted = argv.shift
        if dotted.nil? || dotted.strip.empty?
          Polyrun::Log.warn "polyrun config: need a dotted path (e.g. prepare.env.PLAYWRIGHT_ENV, partition.paths_file, workers)"
          return 2
        end
        unless argv.empty?
          Polyrun::Log.warn "polyrun config: unexpected arguments: #{argv.join(" ")}"
          return 2
        end

        cfg = Polyrun::Config.load(path: config_path || ENV["POLYRUN_CONFIG"])
        val = Polyrun::Config::Effective.dig(cfg, dotted)
        if val.nil?
          Polyrun::Log.warn "polyrun config: no value for #{dotted}"
          return 1
        end

        Polyrun::Log.puts format_config_value(val)
        0
      end

      def format_config_value(val)
        case val
        when Hash, Array
          JSON.generate(val)
        else
          val.to_s
        end
      end
    end
  end
end
