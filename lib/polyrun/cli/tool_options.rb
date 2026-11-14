require_relative "../config"

module Polyrun
  class CLI
    module ToolOptions
      private

      def common_tool_options(parser, options)
        parser.on("--[no-]enable") { |value| options[:enabled] = value }
        parser.on("--root PATH") { |value| options[:root] = value }
        parser.on("--timeout SECONDS", Float) { |value| options[:timeout] = value }
        parser.on("--max-output-bytes N", Integer) { |value| options[:max_output_bytes] = value }
      end

      def configured_tool(feature, overrides)
        root = File.expand_path(overrides[:root] || Dir.pwd)
        cfg = Config.load(path: ENV["POLYRUN_CONFIG"], root: root)
        settings = Config::Tools.resolve(cfg, feature, overrides: overrides, root: root)
        if feature == "mutation"
          graph = Config::Tools.resolve(cfg, "graph", root: root)
          settings["staging"]["exclude_paths"] |= [graph["state_dir"]]
        end
        unless settings["enabled"]
          raise Graph::Error.new("FEATURE_DISABLED", "#{feature} is disabled; enable it in polyrun.yml or use --enable", exitstatus: 2)
        end
        settings
      end

      def extract_tool_command!(argv)
        separator = argv.index("--")
        separator ? argv.slice!(separator..).drop(1) : nil
      end

      def tool_execution_options(settings, *keys)
        settings.slice("root", "timeout", *keys).transform_keys(&:to_sym).merge(max_output: settings["max_output_bytes"])
      end

      def tool_command(settings, explicit)
        command = explicit || settings.fetch("command")
        raise ArgumentError, "a command is required after -- or in configuration" if command.empty?

        command
      end
    end
  end
end
