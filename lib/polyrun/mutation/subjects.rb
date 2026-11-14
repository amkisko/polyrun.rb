require "prism"
require_relative "../graph/plan"

module Polyrun
  module Mutation
    module Subjects
      module_function

      def from_observation(path, max_bytes: 16_777_216)
        raise ArgumentError, "observation is too large" if File.size(path) > max_bytes

        observation = JSON.parse(File.read(path))
        unless observation.is_a?(Hash) && observation["provenance"] == "observed" && observation["calls"].is_a?(Array)
          raise ArgumentError, "invalid observation"
        end
        raise ArgumentError, "truncated observation requires explicit subjects" if observation["truncated"]
        unless observation["calls"].all? { |row| row.is_a?(Hash) && row["subject"].is_a?(String) }
          raise ArgumentError, "observation subjects must be strings"
        end

        observation["calls"].map { |row| row["subject"] }
      end

      def from_plan(root, id, settings: {})
        plan = Graph::Plan.new(root, id, settings: settings)
        plan.verify_originals!
        plan.metadata.fetch("pre_hashes").keys.flat_map do |relative|
          original = File.binread(File.join(root, relative))
          staged = File.binread(File.join(plan.tree, relative))
          next [] if original == staged

          before = definitions(original)
          after = definitions(staged)
          (before.keys | after.keys).select { |subject| before[subject] != after[subject] }
        end.uniq.sort
      end

      def definitions(source)
        parsed = Prism.parse(source)
        raise ArgumentError, "cannot select subjects from invalid Ruby" if parsed.failure?

        result = {}
        walk(parsed.value, [], false, result)
        result
      end

      def walk(node, owners, singleton, result)
        if node.is_a?(Prism::ClassNode) || node.is_a?(Prism::ModuleNode)
          owners = scope_owners(node, owners)
          singleton = false
        elsif node.is_a?(Prism::SingletonClassNode)
          raise ArgumentError, "only self singleton classes support subject selection" unless node.expression.is_a?(Prism::SelfNode)

          singleton = true
        elsif node.is_a?(Prism::DefNode)
          add_definition(node, owners, singleton, result)
          return
        end
        node.compact_child_nodes.each { |child| walk(child, owners, singleton, result) }
      end

      def scope_owners(node, owners)
        name = node.constant_path.full_name
        if !owners.empty? && name.include?("::") && !name.start_with?("::")
          raise ArgumentError, "qualified nested owners require explicit mutation subjects"
        end

        name.start_with?("::") ? [name.delete_prefix("::")] : owners + [name]
      rescue Prism::ConstantPathNode::DynamicPartsInConstantPathError
        raise ArgumentError, "dynamic constant owners require explicit mutation subjects"
      end

      def add_definition(node, owners, singleton, result)
        raise ArgumentError, "top-level methods require explicit mutation subjects" if owners.empty?
        if node.receiver && !node.receiver.is_a?(Prism::SelfNode)
          raise ArgumentError, "dynamic method owners require explicit mutation subjects"
        end

        separator = (singleton || node.receiver) ? "." : "#"
        subject = "#{owners.join("::")}#{separator}#{node.name}"
        raise ArgumentError, "redefined methods require explicit mutation subjects" if result.key?(subject)

        result[subject] = node.location.slice
      end
      private_class_method :definitions, :walk, :scope_owners, :add_definition
    end
  end
end
