module Polyrun
  module Data
    # Process-local memoization for expensive fixture setup (+register+ / +cached+).
    # Use inside +before(:suite)+ or a support file so each parallel **process** builds once; not for threads
    # without external locking (see {ParallelProvisioning}).
    #
    # Example:
    #
    #   Polyrun::Data::CachedFixtures.register(:admin) { User.create!(email: "a@example.com") }
    #   Polyrun::Data::CachedFixtures.fetch(:admin) # => same object
    #
    module CachedFixtures
      # :nodoc:
      class Cache
        attr_reader :store

        def initialize
          @store = {}
          @stats = {}
        end

        def fetch(key, &block)
          k = key.to_s
          if store.key?(k)
            @stats[k][:hits] += 1
            return store[k]
          end

          t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          store[k] = yield
          @stats[k] = {
            build_time: Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0,
            hits: 0
          }
          store[k]
        end

        def clear
          store.clear
          @stats.clear
        end

        def stats_snapshot
          @stats.transform_values(&:dup)
        end
      end

      # Mutable process-local state lives on a plain object so the singleton class avoids class ivars
      # (ThreadSafety/ClassInstanceVariable); still one cache per process, not thread-safe for concurrent threads.
      class Registry
        attr_accessor :disabled
        attr_reader :cache, :callbacks

        def initialize
          @disabled = false
          @cache = Cache.new
          @callbacks = {before_reset: [], after_reset: []}
        end
      end
      private_constant :Registry

      REGISTRY = Registry.new
      private_constant :REGISTRY

      class << self
        def fetch(id, &block)
          return yield if disabled?

          REGISTRY.cache.fetch(id.to_s, &block)
        end

        alias_method :register, :fetch

        def cached(id)
          return unless REGISTRY.cache.store.key?(id.to_s)

          REGISTRY.cache.store[id.to_s]
        end

        def reset!
          REGISTRY.callbacks[:before_reset].each(&:call)
          REGISTRY.cache.clear
          REGISTRY.callbacks[:after_reset].each(&:call)
          REGISTRY.callbacks[:before_reset].clear
          REGISTRY.callbacks[:after_reset].clear
        end

        def before_reset(&block)
          REGISTRY.callbacks[:before_reset] << block if block
        end

        def after_reset(&block)
          REGISTRY.callbacks[:after_reset] << block if block
        end

        def disable!
          REGISTRY.disabled = true
        end

        def enable!
          REGISTRY.disabled = false
        end

        def disabled?
          REGISTRY.disabled == true
        end

        def stats
          REGISTRY.cache.stats_snapshot
        end

        def format_stats_report(title: "Polyrun cached fixtures")
          lines = [title]
          REGISTRY.cache.stats_snapshot.each do |key, s|
            lines << format("  %-40s  build: %0.4fs  hits: %d", key, s[:build_time], s[:hits])
          end
          lines.join("\n") + "\n"
        end
      end
    end
  end
end
