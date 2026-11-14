require "json"
require_relative "../graph/error"

module Polyrun
  class CLI
    module QualityCommands
      private

      def cmd_measure(argv)
        options = {}
        command = extract_tool_command!(argv)
        parser = OptionParser.new do |opts|
          common_tool_options(opts, options)
          opts.on("--label NAME") { |value| options[:label] = value }
          opts.on("--ceilings PATH") { |value| options[:ceilings] = JSON.parse(File.read(value)) }
          opts.on("--output PATH") { |value| options[:output] = value }
        end
        raise ArgumentError, "unexpected measure arguments" unless parser.parse(argv).empty?

        settings = configured_tool("measure", options)
        require_relative "../quality/measure"
        result = Quality::Measure.call(tool_command(settings, command), **tool_execution_options(settings, "label", "ceilings"))
        write_quality_result(result, settings["output"])
        quality_result_status(result)
      rescue OptionParser::ParseError, ArgumentError, SystemCallError, JSON::ParserError, Graph::Error, Psych::Exception => e
        Polyrun::Log.warn "measure: #{e.message}"
        2
      end

      def cmd_observe(argv)
        options = {}
        command = extract_tool_command!(argv)
        parser = OptionParser.new do |opts|
          common_tool_options(opts, options)
          opts.on("--output PATH") { |value| options[:output] = value }
          opts.on("--max-entries N", Integer) { |value| options[:max_entries] = value }
        end
        raise ArgumentError, "unexpected observe arguments" unless parser.parse(argv).empty?

        settings = configured_tool("observe", options)
        require_relative "../quality/observe"
        raise ArgumentError, "--output is required" unless settings["output"]
        result = Quality::Observe.call(tool_command(settings, command), root: settings["root"], output: settings["output"],
          timeout: settings["timeout"], limit: settings["max_entries"], max_output: settings["max_output_bytes"], max_artifact_bytes: settings["max_artifact_bytes"])
        write_quality_result(result, nil)
        quality_result_status(result)
      rescue OptionParser::ParseError, ArgumentError, SystemCallError, JSON::ParserError, Graph::Error, Psych::Exception => e
        Polyrun::Log.warn "observe: #{e.message}"
        2
      end

      def write_quality_result(result, output)
        payload = JSON.generate(result)
        File.write(output, payload + "\n") if output
        Polyrun::Log.puts payload
      end

      def quality_result_status(result)
        return result["exitstatus"] unless result["exitstatus"].zero?

        result["ok"] ? 0 : 1
      end
    end
  end
end
