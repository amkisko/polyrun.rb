require "monitor"

require_relative "../log"

module Polyrun
  class Hooks
    # Ruby DSL for +hooks.ruby+ / +hooks.ruby_file+ in +polyrun.yml+ (see README).
    #
    # Example file (+config/polyrun_hooks.rb+):
    #
    #   before(:suite) { |env| puts env["POLYRUN_HOOK_PHASE"] }
    #   after(:each) { |env| }
    #
    # Blocks receive a hash with string keys (same env as shell hooks).
    module Dsl
      class Registry
        def initialize
          @phases = Hash.new { |h, k| h[k] = [] }
        end

        def add(phase, proc)
          @phases[phase.to_sym] << proc
        end

        # @param env [Hash] string-keyed env
        def run(phase, env)
          @phases[phase.to_sym].each { |pr| pr.call(env) }
        end

        def any?(phase)
          @phases[phase.to_sym].any?
        end

        def empty?
          @phases.values.all?(&:empty?)
        end

        def worker_hooks?
          any?(:before_worker) || any?(:after_worker)
        end
      end

      # Evaluates a hook file with +before+ / +after+ (+before(:suite)+, etc.).
      class FileContext
        def initialize(path)
          @path = path
          @registry = Registry.new
        end

        attr_reader :registry

        def load_file
          instance_eval(File.read(@path), @path)
          @registry
        end

        def before(sym, &block)
          @registry.add(map_before(sym), block)
        end

        def after(sym, &block)
          @registry.add(map_after(sym), block)
        end

        private

        def map_before(sym)
          case sym.to_sym
          when :suite then :before_suite
          when :all then :before_shard
          when :each then :before_worker
          else
            raise ArgumentError, "hooks DSL: before(#{sym.inspect}) — use :suite, :all, or :each"
          end
        end

        def map_after(sym)
          case sym.to_sym
          when :suite then :after_suite
          when :all then :after_shard
          when :each then :after_worker
          else
            raise ArgumentError, "hooks DSL: after(#{sym.inspect}) — use :suite, :all, or :each"
          end
        end
      end

      class << self
        # @return [Registry, nil]
        def load_registry(path)
          return nil if path.nil? || path.to_s.strip.empty?

          full = File.expand_path(path.to_s, Dir.pwd)
          return nil unless File.file?(full)

          mtime = File.mtime(full)
          cache_mu.synchronize do
            hit = registry_cache[full]
            return hit[:registry] if hit && hit[:mtime] == mtime

            reg = FileContext.new(full).load_file
            registry_cache[full] = {mtime: mtime, registry: reg}
            reg
          end
        rescue => e
          Polyrun::Log.warn "polyrun hooks: failed to load #{full}: #{e.class}: #{e.message}"
          nil
        end

        def clear_cache!
          cache_mu.synchronize { registry_cache.clear }
        end

        private

        # rubocop:disable ThreadSafety/ClassInstanceVariable -- single-threaded hook load; Monitor protects cache
        def cache_mu
          @cache_mu ||= Monitor.new
        end

        def registry_cache
          @registry_cache ||= {}
        end
        # rubocop:enable ThreadSafety/ClassInstanceVariable
      end
    end
  end
end
