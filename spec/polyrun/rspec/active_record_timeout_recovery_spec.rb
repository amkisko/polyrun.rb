require "spec_helper"
require "polyrun/rspec/active_record_timeout_recovery"

RSpec.describe Polyrun::RSpec::ActiveRecordTimeoutRecovery do
  describe ".disconnect_all_connection_pools!" do
    it "is a no-op when ActiveRecord is not loaded" do
      hide_const("ActiveRecord::Base") if defined?(ActiveRecord::Base)

      expect { described_class.disconnect_all_connection_pools! }.not_to raise_error
    end

    it "calls ActiveRecord.disconnect_all! when available" do
      active_record_module = Module.new
      active_record_module.define_singleton_method(:disconnect_all!) {}

      base = Class.new do
        def self.connection_handler
          nil
        end
      end

      stub_const("ActiveRecord", active_record_module)
      stub_const("ActiveRecord::Base", base)

      expect(ActiveRecord).to receive(:disconnect_all!)

      described_class.disconnect_all_connection_pools!
    end

    it "disconnects every pool on every connection handler when disconnect_all! is unavailable" do
      primary_pool = instance_double("ConnectionPool", disconnect!: nil)
      cache_pool = instance_double("ConnectionPool", disconnect!: nil)
      primary_handler = instance_double("ConnectionHandler", all_connection_pools: [primary_pool])
      cache_handler = instance_double("ConnectionHandler", all_connection_pools: [cache_pool])

      base = Class.new do
        class << self
          attr_accessor :handlers

          def connection_handlers
            handlers
          end

          def connection_handler
            handlers.values.first
          end
        end
      end
      base.handlers = {"primary" => primary_handler, "cache" => cache_handler}

      stub_const("ActiveRecord::Base", base)

      described_class.disconnect_all_connection_pools!

      expect(primary_pool).to have_received(:disconnect!)
      expect(cache_pool).to have_received(:disconnect!)
    end

    it "falls back to connection_pool_list on older connection handlers" do
      legacy_pool = instance_double("ConnectionPool", disconnect!: nil)
      legacy_handler = instance_double("ConnectionHandler", connection_pool_list: [legacy_pool])

      base = Class.new do
        define_singleton_method(:connection_handler) { legacy_handler }
      end

      stub_const("ActiveRecord::Base", base)

      described_class.disconnect_all_connection_pools!

      expect(legacy_pool).to have_received(:disconnect!)
    end
  end
end
