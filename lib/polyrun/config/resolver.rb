require_relative "../env/ci"
require_relative "../partition/timing_keys"

module Polyrun
  class Config
    # Single source for values derived from +polyrun.yml+, +ENV+, and CI detection.
    # Used by {Effective}, CLI helpers, and prepare.
    module Resolver
      module_function

      def env_int(name, fallback, env = ENV)
        s = env[name]
        return fallback if s.nil? || s.empty?

        Integer(s, exception: false) || fallback
      end

      def prepare_env_yaml_string_map(prep)
        (prep["env"] || prep[:env] || {}).transform_keys(&:to_s).transform_values(&:to_s)
      end

      # Same merge order as +polyrun prepare+: YAML +prepare.env+ overrides process +ENV+ for overlapping keys.
      def merged_prepare_env(prep, env = ENV)
        prep_env = prepare_env_yaml_string_map(prep)
        env.to_h.merge(prep_env)
      end

      def partition_int(pc, keys, default)
        keys.each do |k|
          v = pc[k] || pc[k.to_sym]
          next if v.nil? || v.to_s.empty?

          i = Integer(v, exception: false)
          return i unless i.nil?
        end
        default
      end

      def resolve_shard_index(pc, env = ENV)
        return Integer(env["POLYRUN_SHARD_INDEX"]) if env["POLYRUN_SHARD_INDEX"] && !env["POLYRUN_SHARD_INDEX"].empty?

        ci = Polyrun::Env::Ci.detect_shard_index
        return ci unless ci.nil?

        partition_int(pc, %w[shard_index shard], 0)
      end

      def resolve_shard_total(pc, env = ENV)
        return Integer(env["POLYRUN_SHARD_TOTAL"]) if env["POLYRUN_SHARD_TOTAL"] && !env["POLYRUN_SHARD_TOTAL"].empty?

        ci = Polyrun::Env::Ci.detect_shard_total
        return ci unless ci.nil?

        partition_int(pc, %w[shard_total total], 1)
      end

      # +cli_val+ is an override (e.g. +run-shards --timing-granularity+); +nil+ uses YAML then +POLYRUN_TIMING_GRANULARITY+.
      def resolve_partition_timing_granularity(pc, cli_val, env = ENV)
        raw = cli_val
        raw ||= pc && (pc["timing_granularity"] || pc[:timing_granularity])
        raw ||= env["POLYRUN_TIMING_GRANULARITY"]
        Polyrun::Partition::TimingKeys.normalize_granularity(raw || "file")
      end

      def parallel_worker_count_default(env = ENV)
        env_int("POLYRUN_WORKERS", Polyrun::Config::DEFAULT_PARALLEL_WORKERS, env)
      end
    end
  end
end
