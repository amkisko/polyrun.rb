module Polyrun
  module RSpec
    # Formatter tweaks for progress bars (e.g. Fuubar) under +POLYRUN_SHARD_*+ workers.
    module ShardedFormatterCompat
      module_function

      def install!(rspec_config: fetch_rspec_configuration!)
        return unless sharded_worker?

        rspec_config.silence_filter_announcements = true
        noop_fuubar_seed! if defined?(Fuubar)
      end

      def sharded_worker?
        !ENV["POLYRUN_SHARD_TOTAL"].to_s.strip.empty?
      end

      def noop_fuubar_seed!
        return unless defined?(Fuubar)

        Fuubar.class_eval do
          def seed(_notification)
          end
        end
      end

      def fetch_rspec_configuration!
        require "rspec/core"
        ::RSpec.configuration
      end
      private_class_method :fetch_rspec_configuration!
    end
  end
end
