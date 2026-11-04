require_relative "../config/schema"

module Polyrun
  class CLI
    module ValidateCommand
      private

      def cmd_validate(argv, config_path)
        unless argv.empty?
          Polyrun::Log.warn "polyrun validate: unexpected arguments: #{argv.join(" ")}"
          return 2
        end

        cfg = Polyrun::Config.load(path: config_path || ENV["POLYRUN_CONFIG"])
        result = Polyrun::Config::Schema.validate(cfg)
        result[:messages].each { |m| Polyrun::Log.warn m }
        if result[:ok]
          Polyrun::Log.puts "polyrun validate: ok (#{cfg.path || "no file"})"
          0
        else
          1
        end
      end
    end
  end
end
