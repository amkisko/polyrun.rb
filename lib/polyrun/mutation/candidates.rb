require "prism"
require "digest"
require_relative "../graph/syntax"
require_relative "../graph/workspace"
require_relative "operators"

module Polyrun
  module Mutation
    class Candidates
      def initialize(root, operators: nil, limit: nil, settings: {})
        settings = Config::Tools.runtime("mutation", settings)
        graph = settings.slice(*Config::ToolDefaults.for("graph").keys)
        @workspace = Graph::Workspace.new(root, settings: graph)
        @operators = operators || Operators.select(settings["operators"])
        @limit = limit || settings["max_mutations"]
        @count = 0
        @seen = {}
      end

      def call(subjects)
        inventory = source_inventory
        subjects.flat_map do |subject|
          matches = select_methods(inventory, subject)
          matches.flat_map { |path, source, method| generate(path, source, method) }
        end.uniq { |mutation| [mutation["path"], mutation["source_hash"]] }
      end

      private

      def source_inventory
        nodes = 0
        @workspace.hashes.keys.map do |relative|
          source = File.binread(@workspace.path(relative))
          syntax = Graph::Syntax.new(relative, source, max_nodes: @workspace.settings["max_nodes"]).parse
          nodes += syntax.methods.size + syntax.calls.size
          raise ArgumentError, "mutation source exceeds configured node limit" if nodes > @workspace.settings["max_nodes"]

          [relative, source, syntax.methods]
        end
      end

      def select_methods(inventory, subject)
        matches = inventory.flat_map { |path, source, methods| methods.filter_map { |method| [path, source, method] if match?(subject, method["subject"]) } }
        raise ArgumentError, "unknown mutation subject: #{subject}" if matches.empty?
        names = matches.map { |_, _, method| method["subject"] }
        raise ArgumentError, "ambiguous mutation subject: #{subject}" unless names.uniq.length == names.length

        matches
      end

      def match?(selector, subject)
        subject && (selector == subject || (selector.include?("*") && File.fnmatch?(selector, subject)))
      end

      def generate(path, source, method)
        parsed = Prism.parse(source)
        nodes = [parsed.value]
        edits = []
        until nodes.empty?
          node = nodes.pop
          location = node.location
          if location.start_offset >= method["byte_start"] && location.end_offset <= method["byte_end"]
            @operators.each { |operator| edits.concat(operator.call(node)) }
          end
          nodes.concat(node.compact_child_nodes)
        end
        edits.filter_map do |location, replacement, operator|
          next if source.byteslice(location.start_offset, location.length) == replacement

          changed = source.byteslice(0, location.start_offset) + replacement.b + source.byteslice(location.end_offset..)
          next if Prism.parse(changed).failure?

          build_candidate(path, source, changed, method, location, replacement, operator)
        end
      end

      def build_candidate(path, source, changed, method, location, replacement, operator)
        digest = Digest::SHA256.hexdigest(changed)
        return if @seen[[path, digest]]

        @seen[[path, digest]] = true
        @count += 1
        raise ArgumentError, "mutation limit exceeded; narrow subjects or raise --max-mutations" if @count > @limit

        {"id" => "mutation-#{Digest::SHA256.hexdigest(path + digest)[0, 24]}", "subject" => method["subject"],
         "path" => path, "line" => location.start_line, "operator" => operator, "start" => location.start_offset,
         "end" => location.end_offset, "replacement" => replacement, "original_hash" => Digest::SHA256.hexdigest(source), "source_hash" => digest}
      end
    end
  end
end
