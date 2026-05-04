require "yaml"

require_relative "../partition/timing_keys"

module Polyrun
  class CLI
    module Helpers
      private

      def env_int(name, fallback)
        Polyrun::Config::Resolver.env_int(name, fallback)
      end

      # Per-worker wall clock (from spawn) for run-shards / ci-shard fan-out; unset or invalid means no limit.
      def env_worker_timeout_sec
        s = ENV["POLYRUN_WORKER_TIMEOUT_SEC"].to_s.strip
        return nil if s.empty?

        f = Float(s, exception: false)
        return nil if f.nil? || f <= 0

        f
      end

      # Max seconds without a new monotonic timestamp ping in the worker (see +polyrun/worker_ping+).
      def env_worker_idle_timeout_sec
        s = ENV["POLYRUN_WORKER_IDLE_TIMEOUT_SEC"].to_s.strip
        return nil if s.empty?

        f = Float(s, exception: false)
        return nil if f.nil? || f <= 0

        f
      end

      def resolve_shard_index(pc)
        Polyrun::Config::Resolver.resolve_shard_index(pc)
      end

      def resolve_shard_total(pc)
        Polyrun::Config::Resolver.resolve_shard_total(pc)
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
      def queue_weight_for(path, costs, default_weight = nil, granularity: :file)
        g = Polyrun::Partition::TimingKeys.normalize_granularity(granularity)
        key =
          if g == :example
            Polyrun::Partition::TimingKeys.normalize_locator(path.to_s, Dir.pwd, :example)
          else
            File.expand_path(path.to_s, Dir.pwd)
          end
        return costs[key] if costs.key?(key)

        unless default_weight.nil?
          return default_weight
        end

        vals = costs.values
        return 1.0 if vals.empty?

        vals.sum / vals.size.to_f
      end

      # CLI + polyrun.yml + POLYRUN_TIMING_GRANULARITY; default +:file+.
      def resolve_partition_timing_granularity(pc, cli_val)
        Polyrun::Config::Resolver.resolve_partition_timing_granularity(pc, cli_val)
      end
    end
  end
end
