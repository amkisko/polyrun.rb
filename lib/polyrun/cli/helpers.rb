require "yaml"

module Polyrun
  class CLI
    module Helpers
      private

      def partition_int(pc, keys, default)
        keys.each do |k|
          v = pc[k] || pc[k.to_sym]
          next if v.nil? || v.to_s.empty?

          i = Integer(v, exception: false)
          return i unless i.nil?
        end
        default
      end

      def env_int(name, fallback)
        s = ENV[name]
        return fallback if s.nil? || s.empty?

        Integer(s, exception: false) || fallback
      end

      def resolve_shard_index(pc)
        return Integer(ENV["POLYRUN_SHARD_INDEX"]) if ENV["POLYRUN_SHARD_INDEX"] && !ENV["POLYRUN_SHARD_INDEX"].empty?

        ci = Polyrun::Env::Ci.detect_shard_index
        return ci unless ci.nil?

        partition_int(pc, %w[shard_index shard], 0)
      end

      def resolve_shard_total(pc)
        return Integer(ENV["POLYRUN_SHARD_TOTAL"]) if ENV["POLYRUN_SHARD_TOTAL"] && !ENV["POLYRUN_SHARD_TOTAL"].empty?

        ci = Polyrun::Env::Ci.detect_shard_total
        return ci unless ci.nil?

        partition_int(pc, %w[shard_total total], 1)
      end

      def expand_merge_input_pattern(path)
        p = path.to_s
        abs = File.expand_path(p, Dir.pwd)
        return Dir.glob(abs).sort if p.include?("*") || p.include?("?")

        [abs]
      end

      # Same rounding/strict semantics as {Polyrun::Coverage::Collector} for +config/polyrun_coverage.yml+.
      def coverage_minimum_line_gate_from_polyrun_coverage_yml
        path = File.join(Dir.pwd, "config", "polyrun_coverage.yml")
        return nil unless File.file?(path)

        data = YAML.safe_load_file(path, permitted_classes: [Symbol], aliases: true)
        return nil unless data.is_a?(Hash)

        min = data["minimum_line_percent"] || data[:minimum_line_percent]
        return nil if min.nil?

        sv = data["strict"] if data.key?("strict")
        sv = data[:strict] if !data.key?("strict") && data.key?(:strict)
        strict = sv.nil? || sv

        {minimum: min.to_f, strict: strict != false}
      rescue Psych::SyntaxError, ArgumentError, TypeError
        nil
      end

      def load_partition_constraints(pc, constraints_path)
        if constraints_path
          path = File.expand_path(constraints_path.to_s, Dir.pwd)
          unless File.file?(path)
            Polyrun::Log.warn "polyrun: constraints file not found: #{path}"
            return nil
          end
          h = YAML.safe_load_file(path, permitted_classes: [Symbol], aliases: true)
          return Polyrun::Partition::Constraints.from_hash(h, root: Dir.pwd)
        end
        if pc["constraints"].is_a?(Hash)
          return Polyrun::Partition::Constraints.from_hash(pc["constraints"], root: Dir.pwd)
        end
        cf = pc["constraints_file"] || pc[:constraints_file]
        if cf
          path = File.expand_path(cf.to_s, Dir.pwd)
          return nil unless File.file?(path)

          h = YAML.safe_load_file(path, permitted_classes: [Symbol], aliases: true)
          return Polyrun::Partition::Constraints.from_hash(h, root: Dir.pwd)
        end
        nil
      end

      # +default_weight+ should be precomputed when sorting many paths (e.g. +queue init+), matching
      # {Partition::Plan#default_weight} semantics: mean of known timing costs for missing paths.
      def queue_weight_for(path, costs, default_weight = nil)
        abs = File.expand_path(path.to_s, Dir.pwd)
        return costs[abs] if costs.key?(abs)

        unless default_weight.nil?
          return default_weight
        end

        vals = costs.values
        return 1.0 if vals.empty?

        vals.sum / vals.size.to_f
      end
    end
  end
end
