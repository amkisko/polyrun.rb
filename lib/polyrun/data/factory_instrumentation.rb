module Polyrun
  module Data
    # Opt-in FactoryBot hook so {#FactoryCounts} sees every factory run (minimal patch).
    # Requires the +factory_bot+ gem and must run after FactoryBot is loaded.
    #
    #   require "factory_bot"
    #   Polyrun::Data::FactoryInstrumentation.instrument_factory_bot!
    module FactoryInstrumentation
      class << self
        def instrument_factory_bot!
          return false unless defined?(FactoryBot)

          factory_class = resolve_factory_runner_class
          return false unless factory_class

          return true if factory_class.instance_variable_defined?(:@polyrun_factory_instrumented) &&
            factory_class.instance_variable_get(:@polyrun_factory_instrumented)

          patch = Module.new do
            def run(...)
              Polyrun::Data::FactoryCounts.record(name)
              super
            end
          end
          factory_class.prepend(patch)
          factory_class.instance_variable_set(:@polyrun_factory_instrumented, true)
          true
        end

        def instrumented?
          return false unless defined?(FactoryBot)

          fc = resolve_factory_runner_class
          return false unless fc

          fc.instance_variable_defined?(:@polyrun_factory_instrumented) &&
            fc.instance_variable_get(:@polyrun_factory_instrumented)
        end

        private

        def resolve_factory_runner_class
          return FactoryBot::Factory if defined?(FactoryBot::Factory)

          nil
        end
      end
    end
  end
end
