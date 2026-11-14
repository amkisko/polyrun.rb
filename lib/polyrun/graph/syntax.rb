require "prism"
require "digest"
require_relative "error"
require_relative "../config/tool_defaults"

module Polyrun
  module Graph
    class Syntax < Prism::Visitor
      attr_reader :methods, :calls

      def initialize(path, source, max_nodes: Config::ToolDefaults::COMMON.fetch("max_nodes"))
        @max_nodes = max_nodes
        @path = path
        @source = source
        @methods = []
        @calls = []
        @owner = "Object"
        @singleton = false
        @method = nil
      end

      def parse
        parsed = Prism.parse(@source)
        raise Error.new("PARSE_FAILED", "invalid Ruby: #{@path}") if parsed.failure?

        parsed.value.accept(self)
        self
      end

      def visit_class_node(node)
        scope(node.constant_path) { node.body&.accept(self) }
      end

      def visit_module_node(node)
        scope(node.constant_path) { node.body&.accept(self) }
      end

      def visit_singleton_class_node(node)
        previous = [@owner, @singleton]
        @owner = constant_name(node.expression) unless node.expression.is_a?(Prism::SelfNode)
        @singleton = true
        node.body&.accept(self)
      ensure
        @owner, @singleton = previous
      end

      def visit_def_node(node)
        previous = @method
        owner = (node.receiver && !node.receiver.is_a?(Prism::SelfNode)) ? constant_name(node.receiver) : @owner
        singleton = @singleton || !node.receiver.nil?
        @method = entry("method", node.name.to_s, node.location).merge("owner" => owner,
          "scope" => singleton ? "singleton" : "instance", "subject" => owner && "#{owner}#{singleton ? "." : "#"}#{node.name}",
          "body_start" => node.body&.location&.start_offset, "body_end" => node.body&.location&.end_offset)
        @methods << @method
        super
      ensure
        @method = previous
      end

      def visit_call_node(node)
        if node.message_loc
          receiver = if node.receiver.nil?
            nil
          elsif node.receiver.is_a?(Prism::SelfNode)
            "self"
          else
            constant_name(node.receiver) || "dynamic"
          end
          @calls << entry("call", node.name.to_s, node.message_loc).merge("method_id" => @method&.fetch("id"),
            "owner" => @method ? @method["owner"] : @owner, "scope" => @method ? @method["scope"] : "singleton", "receiver" => receiver)
        end
        super
      end

      private

      def scope(node)
        previous = [@owner, @singleton, @method]
        name = constant_name(node)
        @owner = if name.nil? || @owner.nil?
          nil
        elsif name.start_with?("::") || @owner == "Object"
          name.delete_prefix("::")
        elsif name.include?("::")
          nil
        else
          [@owner, name].compact.join("::")
        end
        @singleton = false
        @method = nil
        yield
      ensure
        @owner, @singleton, @method = previous
      end

      def constant_name(node)
        node.full_name if node.is_a?(Prism::ConstantReadNode) || node.is_a?(Prism::ConstantPathNode)
      rescue Prism::ConstantPathNode::DynamicPartsInConstantPathError
        nil
      end

      def entry(kind, name, location)
        raise Error.new("RESOURCE_LIMIT", "too many graph nodes") if @methods.size + @calls.size >= @max_nodes

        bytes = @source.byteslice(location.start_offset, location.length)
        fingerprint = Digest::SHA256.hexdigest(bytes)
        identity = Digest::SHA256.hexdigest([kind, @path, location.start_offset, fingerprint].join("\0"))
        {"id" => "#{kind}-#{identity[0, 24]}", "kind" => kind, "name" => name, "path" => @path,
         "line" => location.start_line, "byte_start" => location.start_offset, "byte_end" => location.end_offset,
         "fingerprint" => fingerprint, "provenance" => "syntax"}
      end
    end
  end
end
