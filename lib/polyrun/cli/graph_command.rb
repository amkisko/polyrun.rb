require "json"
require_relative "../graph/error"

module Polyrun
  class CLI
    module GraphCommand
      private

      def cmd_graph(argv)
        options = {}
        json = argv.include?("--json")
        explicit = extract_tool_command!(argv)
        positional = parse_graph_options(argv, options)
        settings = configured_tool("graph", options)
        require_relative "../graph/client"
        json = settings["json"]
        proving = (positional.first == "check") ? settings["prove"] : options.fetch(:prove, false)
        prove = proving ? tool_command(settings, explicit) : (explicit || [])
        validate_graph_arguments!(positional, proving, prove)
        forwarded = %w[json calls callers callees control_plane].filter_map { |flag| "--#{flag.tr("_", "-")}" if settings[flag] }
        result = Graph::Client.new(root: settings["root"], settings: settings).call(positional + forwarded, prove: prove)
        emit_graph_result(result, settings["output"])
      rescue Graph::Error => e
        graph_diagnostic(e.code, e.message, json)
        e.exitstatus
      rescue OptionParser::ParseError, ArgumentError, KeyError, SystemCallError, Psych::Exception => e
        graph_diagnostic("INVALID_ARGUMENT", e.message, json)
        2
      end

      def parse_graph_options(argv, options)
        parser = OptionParser.new do |opts|
          common_tool_options(opts, options)
          %w[json calls callers callees control-plane prove].each do |flag|
            opts.on("--[no-]#{flag}") { |value| options[flag.tr("-", "_").to_sym] = value }
          end
        end
        parser.parse(argv)
      end

      def validate_graph_arguments!(positional, proving, prove)
        verb = positional.first
        unless %w[index inspect plan check apply].include?(verb)
          raise ArgumentError, "usage: polyrun graph index|inspect|plan|check|apply [options]"
        end
        required = %w[plan check apply].include?(verb) ? 2 : 1
        maximum = (verb == "inspect") ? 2 : required
        raise ArgumentError, "graph #{verb}: invalid arguments" unless (required..maximum).cover?(positional.length)
        raise ArgumentError, "--prove requires graph check and a command after --" if (proving || !prove.empty?) && (verb != "check" || !proving || prove.empty?)
      end

      def emit_graph_result(result, output = nil)
        if [122, 124, 127].include?(result["exitstatus"])
          code = {122 => "OUTPUT_LIMIT", 124 => "TIMEOUT", 127 => "WORKER_UNAVAILABLE"}.fetch(result["exitstatus"])
          raise Graph::Error.new(code, "graph command failed (#{code.downcase.tr("_", " ")})", exitstatus: result["exitstatus"])
        end
        File.write(output, result["exitstatus"].zero? ? result["stdout"] : result["stderr"]) if output
        Polyrun::Log.print result["stdout"]
        Polyrun.stderr.write(result["stderr"])
        result["exitstatus"]
      end

      def graph_diagnostic(code, message, json)
        Polyrun::Log.warn(json ? JSON.generate("ok" => false, "code" => code, "message" => message) : "#{code}: #{message}")
      end
    end
  end
end
