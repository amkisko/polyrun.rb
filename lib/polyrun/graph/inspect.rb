require_relative "index"

module Polyrun
  module Graph
    class Inspect
      def initialize(index)
        @index = index
      end

      def call(selector, flags)
        return control_plane if flags.include?("--control-plane")

        methods = select_methods(selector)
        raise Error.new("UNKNOWN_TARGET", "no matching method") if methods.empty?
        raise Error.new("AMBIGUOUS_NODE", "choose a method owner or source path") unless methods.one?

        nodes = methods.map do |method|
          value = method.dup
          value["calls"] = @index["calls"].select { |node| node["method_id"] == method["id"] } if flags.include?("--calls")
          %w[callers callees].each do |direction|
            next unless flags.include?("--#{direction}")

            value[direction] = connections(method, direction)
          end
          value
        end
        {"ok" => true, "snapshot" => @index["snapshot"], "nodes" => nodes}
      end

      private

      def connections(method, direction)
        lookup = @index["methods"].to_h { |entry| [entry["id"], entry] }
        from, to = (direction == "callers") ? %w[to_id from_id] : %w[from_id to_id]
        @index["edges"].select { |edge| edge[from] == method["id"] }.map do |edge|
          lookup.fetch(edge[to]).merge("provenance" => edge["provenance"])
        end
      end

      def select_methods(selector)
        if selector&.start_with?("path:")
          path, name = selector.delete_prefix("path:").split("#", 2)
          @index["methods"].select { |method| method["path"] == path && (!name || method["name"] == name) }
        else
          @index["methods"].select { |method| [method["id"], method["subject"], method["name"]].include?(selector) }
        end
      end

      def control_plane
        lifecycle = @index["methods"].select { |method| method["name"].match?(/\A(?:start|stop|shutdown|run|perform|call|process|poll|tick|schedule)[!?]?\z/) }
        signals = @index["calls"].select { |node| node["name"].match?(/\A(?:notify|broadcast|signal|enqueue|publish|perform_async)[!?]?\z/) }
        signal_ids = signals.to_h { |node| [node["id"], true] }
        {"ok" => true, "snapshot" => @index["snapshot"], "control_plane" => {"lifecycle" => lifecycle,
                                                                             "signals" => signals, "signal_edges" => @index["edges"].select { |edge| signal_ids[edge["call_id"]] }}}
      end
    end
  end
end
