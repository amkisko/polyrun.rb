module Polyrun
  module Data
    # Branching helpers for **serial** vs **parallel worker** test DB setup (seeds, truncate).
    # Polyrun does not call Rails +truncate+ or +load_seed+ for you — wire those in the callbacks you assign.
    #
    # Typical split (empty parallel DBs get seeds only; serial run truncates then seeds):
    #
    #   Polyrun::Data::ParallelProvisioning.configure do |c|
    #     c.serial { replant_and_load_seed }
    #     c.parallel_worker { load_seed_only }
    #   end
    #   # In spec_helper after configure:
    #   Polyrun::Data::ParallelProvisioning.run_suite_hooks!
    #
    # Or use {Polyrun::RSpec.install_parallel_provisioning!} (+before(:suite)+) or {Polyrun::Minitest.install_parallel_provisioning!}
    # (+require+ +polyrun/minitest+ from +test/test_helper.rb+).
    module ParallelProvisioning
      class Configuration
        attr_accessor :serial_hook, :parallel_worker_hook

        def serial(&block)
          self.serial_hook = block if block
        end

        def parallel_worker(&block)
          self.parallel_worker_hook = block if block
        end
      end

      class Storage
        attr_accessor :configuration

        def initialize
          @configuration = Configuration.new
        end
      end
      private_constant :Storage

      STORAGE = Storage.new
      private_constant :STORAGE

      class << self
        def configure
          yield configuration
        end

        def configuration
          STORAGE.configuration
        end

        def reset_configuration!
          STORAGE.configuration = Configuration.new
        end

        # True when multiple shards are in use ({Database::Shard} sets +POLYRUN_SHARD_TOTAL+).
        def parallel_workers?
          shard_total > 1
        end

        # 0-based worker index; prefers +POLYRUN_SHARD_INDEX+, else derives from +TEST_ENV_NUMBER+ (parallel_tests).
        def shard_index
          if (s = ENV["POLYRUN_SHARD_INDEX"]) && !s.to_s.empty?
            Integer(s)
          elsif (n = ENV["TEST_ENV_NUMBER"]).to_s.empty? || n == "0"
            0
          else
            Integer(n) - 1
          end
        rescue ArgumentError
          0
        end

        def shard_total
          t = ENV["POLYRUN_SHARD_TOTAL"]
          return Integer(t) if t && !t.to_s.empty?

          1
        rescue ArgumentError
          1
        end

        # Runs +parallel_worker_hook+ when {#parallel_workers?}, else +serial_hook+. No-op if the chosen hook is nil.
        def run_suite_hooks!
          if parallel_workers?
            configuration.parallel_worker_hook&.call
          else
            configuration.serial_hook&.call
          end
        end
      end
    end
  end
end
