require_relative "workspace"
require_relative "syntax"

module Polyrun
  module Graph
    class Index
      def initialize(root, settings: {})
        @workspace = Workspace.new(root, settings: settings)
      end

      def call
        hashes = @workspace.hashes
        snapshot = @workspace.snapshot(hashes)
        existing = cached_index(snapshot)
        return existing if existing

        methods = []
        calls = []
        hashes.each_key do |relative|
          syntax = Syntax.new(relative, File.binread(@workspace.path(relative)), max_nodes: @workspace.settings["max_nodes"]).parse
          methods.concat(syntax.methods)
          calls.concat(syntax.calls)
          enforce_node_limit!(methods.size + calls.size)
        end
        raise Error.new("STALE_SNAPSHOT", "source changed while indexing") unless @workspace.hashes == hashes

        edges = resolve(methods, calls)
        @workspace.write_json("#{@workspace.state}/index.json", {"format" => 1, "snapshot" => snapshot,
          "files" => hashes, "methods" => methods, "calls" => calls, "edges" => edges, "reused" => false})
      end

      def load
        value = @workspace.read_json("#{@workspace.state}/index.json")
        unless value.is_a?(Hash) && value["format"] == 1 && %w[methods calls edges].all? { |key| value[key].is_a?(Array) }
          raise Error.new("INVALID_PLAN", "invalid graph index")
        end
        value
      end

      private

      def cached_index(snapshot)
        return unless File.file?(@workspace.path("#{@workspace.state}/index.json"))

        existing = load
        return unless existing["snapshot"] == snapshot

        enforce_node_limit!(existing["methods"].size + existing["calls"].size)
        existing.merge("reused" => true)
      end

      def enforce_node_limit!(count)
        raise Error.new("RESOURCE_LIMIT", "too many graph nodes") if count > @workspace.settings["max_nodes"]
      end

      def resolve(methods, calls)
        lookup = methods.group_by { |method| [method["owner"], method["scope"], method["name"]] }
        calls.filter_map do |call|
          owner, scope = if call["receiver"].nil? || call["receiver"] == "self"
            [call["owner"], call["scope"]]
          else
            [call["receiver"].delete_prefix("::"), "singleton"]
          end
          candidates = owner && lookup[[owner, scope, call["name"]]]
          target = candidates&.one? ? candidates.first : nil
          call["target"] = target && target["id"]
          call["target_provenance"] = target ? "static_guess" : "unknown"
          next unless target && call["method_id"]

          {"from_id" => call["method_id"], "to_id" => target["id"], "call_id" => call["id"], "provenance" => "static_guess"}
        end
      end
    end
  end
end
