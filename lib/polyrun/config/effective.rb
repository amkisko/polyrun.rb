require_relative "dotted_path"
require_relative "resolver"

module Polyrun
  class Config
    # Nested hash of values Polyrun uses: loaded YAML (string keys) with overlays for
    # merged +prepare.env+, resolved +partition.shard_index+ / +shard_total+ / +timing_granularity+,
    # and top-level +workers+ (+POLYRUN_WORKERS+ default).
    #
    # +build+ memoizes the last (cfg, env) in-process so repeated +dig+ calls on the same load do not
    # rebuild the tree (single-threaded CLI).
    module Effective
      class << self
        # Per-thread cache avoids rebuilding the effective tree on repeated +dig+; no class ivars (RuboCop ThreadSafety).
        def build(cfg, env: ENV)
          key = cache_key(cfg, env)
          per_thread = (Thread.current[:polyrun_effective_build] ||= {})
          per_thread[key] ||= build_uncached(cfg, env: env)
        end

        def dig(cfg, dotted_path, env: ENV)
          Polyrun::Config::DottedPath.dig(build(cfg, env: env), dotted_path)
        end

        private

        def cache_key(cfg, env)
          [cfg.path, cfg.object_id, env_fingerprint(env)]
        end

        def env_fingerprint(env)
          env.to_h.keys.sort.map { |k| [k, env[k]] }.hash
        end

        def build_uncached(cfg, env:)
          r = Polyrun::Config::Resolver
          base = deep_stringify_keys(cfg.raw)

          prep = cfg.prepare
          base["prepare"] = deep_stringify_keys(prep)
          base["prepare"]["env"] = r.merged_prepare_env(prep, env)

          pc = cfg.partition
          part = deep_stringify_keys(pc).merge(
            "shard_index" => r.resolve_shard_index(pc, env),
            "shard_total" => r.resolve_shard_total(pc, env),
            "timing_granularity" => r.resolve_partition_timing_granularity(pc, nil, env).to_s
          )
          base["partition"] = part

          base["workers"] = r.parallel_worker_count_default(env)

          base
        end

        def deep_stringify_keys(obj)
          case obj
          when Hash
            obj.each_with_object({}) do |(k, v), m|
              m[k.to_s] = deep_stringify_keys(v)
            end
          when Array
            obj.map { |e| deep_stringify_keys(e) }
          else
            obj
          end
        end
      end
    end
  end
end
