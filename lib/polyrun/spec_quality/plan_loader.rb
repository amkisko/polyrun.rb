require "json"

module Polyrun
  module SpecQuality
    # Loads partition plan JSON for spec-quality ↔ shard correlation.
    module PlanLoader
      module_function

      # @param paths [Array<String>] plan JSON files (+polyrun plan+ output per shard or a wrapper hash)
      # @return [Hash{String=>Array<String>}] shard index string => spec file paths
      def load_shards(paths)
        out = {}
        Array(paths).each do |path|
          next unless File.file?(path)

          data = JSON.parse(File.read(File.expand_path(path)))
          merge_plan_data!(out, data)
        end
        out
      end

      def merge_plan_data!(out, data)
        if data.is_a?(Hash) && data["shards"].is_a?(Hash)
          data["shards"].each { |k, v| out[k.to_s] = Array(v).map(&:to_s) }
          return
        end

        return unless data.is_a?(Hash)

        shard = data["shard_index"]
        paths = data["paths"]
        return if shard.nil? || !paths.is_a?(Array)

        out[shard.to_s] = paths.map(&:to_s)
      end

      # @return [String, nil] shard index for an example locator given plan shards
      def shard_for_example(example_loc, plan_shards)
        file = example_loc.to_s.sub(/:\d+\z/, "")
        plan_shards.each do |shard, paths|
          return shard if paths.any? { |p| file == p || file.end_with?("/#{File.basename(p)}") || file.include?(p) }
        end
        nil
      end
    end
  end
end
