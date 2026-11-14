require "json"
require_relative "planner"
require_relative "inspect"

module Polyrun
  module Graph
    module Worker
      module_function

      def run(arguments)
        root = ENV.fetch("POLYRUN_GRAPH_ROOT", Dir.pwd)
        json = arguments.include?("--json")
        arguments = arguments.reject { |argument| argument == "--json" }
        settings = JSON.parse(ENV.delete("POLYRUN_GRAPH_SETTINGS") || "{}")
        result = dispatch(root, arguments, settings)
        puts(json ? JSON.generate(result) : text_result(arguments.first, result))
        0
      rescue Error => error
        warn(json ? JSON.generate("ok" => false, "code" => error.code, "message" => error.message) : "#{error.code}: #{error.message}")
        error.exitstatus
      rescue SystemCallError, ArgumentError, KeyError, JSON::ParserError => error
        warn(json ? JSON.generate("ok" => false, "code" => "INVALID_ARGUMENT", "message" => error.message) : error.message)
        2
      end

      def dispatch(root, arguments, settings)
        verb, argument, *flags = arguments
        index = Index.new(root, settings: settings)
        case verb
        when "index"
          graph = index.call
          {"ok" => true, "snapshot" => graph["snapshot"], "nodes" => graph["methods"].size + graph["calls"].size, "reused" => graph["reused"]}
        when "inspect" then Inspect.new(index.load).call(argument, flags + (argument&.start_with?("--") ? [argument] : []))
        when "plan" then Planner.new(root, settings: settings).call(argument)
        when "check" then Plan.new(root, argument, settings: settings).check!
        when "apply"
          Plan.new(root, argument, settings: settings).apply!
          {"ok" => true, "plan_id" => argument, "applied" => true, "snapshot" => index.call["snapshot"]}
        else raise Error.new("INVALID_ARGUMENT", "unknown graph command")
        end
      end

      def text_result(verb, result)
        case verb
        when "index" then "indexed #{result["snapshot"]} nodes=#{result["nodes"]} reused=#{result["reused"]}"
        when "plan" then "plan #{result["plan_id"]}\n#{result["diff"]}"
        when "check" then "checked plan: #{result["status"]}"
        when "apply" then "applied #{result["plan_id"]}"
        else JSON.pretty_generate(result)
        end
      end
      private_class_method :dispatch, :text_result
    end
  end
end
