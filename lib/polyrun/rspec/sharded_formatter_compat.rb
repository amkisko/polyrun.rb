module Polyrun
  module RSpec
    # Formatter tweaks for progress formatters under +POLYRUN_SHARD_*+ workers.
    module ShardedFormatterCompat
      TextFormatterSilencer = Module.new do
        def seed(_notification)
        end

        def dump_summary(_notification)
        end

        def dump_pending(_notification)
        end
      end

      FuubarSeedSilencer = Module.new do
        def seed(_notification)
        end
      end

      module_function

      def install!(rspec_config: fetch_rspec_configuration!)
        return unless sharded_worker?

        rspec_config.silence_filter_announcements = true
        silence_text_formatter_noise!
        silence_fuubar_seed! if defined?(Fuubar)
      end

      def sharded_worker?
        !ENV["POLYRUN_SHARD_TOTAL"].to_s.strip.empty?
      end

      def silence_text_formatter_noise!
        require "rspec/core/formatters/base_text_formatter"
        klass = ::RSpec::Core::Formatters::BaseTextFormatter
        return if klass.ancestors.include?(TextFormatterSilencer)

        klass.prepend(TextFormatterSilencer)
      end

      def silence_fuubar_seed!
        return unless defined?(Fuubar)
        return if Fuubar.ancestors.include?(FuubarSeedSilencer)

        Fuubar.prepend(FuubarSeedSilencer)
      end

      def fetch_rspec_configuration!
        require "rspec/core"
        ::RSpec.configuration
      end
      private_class_method :fetch_rspec_configuration!
    end
  end
end
