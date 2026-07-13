require "spec_helper"
require "polyrun/rspec/example_debug"

RSpec.describe Polyrun::RSpec::ExampleDebug do
  describe ".install_example_timeout!" do
    around do |example|
      old = ENV["POLYRUN_EXAMPLE_DEBUG"]
      ENV.delete("POLYRUN_EXAMPLE_DEBUG")
      example.run
    ensure
      old.nil? ? ENV.delete("POLYRUN_EXAMPLE_DEBUG") : ENV["POLYRUN_EXAMPLE_DEBUG"] = old
    end

    it "registers without error" do
      config = ::RSpec::Core::Configuration.new
      expect { described_class.install_example_timeout!(config, seconds: 5) }.not_to raise_error
    end

    it "disconnects ActiveRecord pools when an example times out" do
      recovery = class_double(
        "Polyrun::RSpec::ActiveRecordTimeoutRecovery",
        disconnect_all_connection_pools!: nil
      )
      stub_const("Polyrun::RSpec::ActiveRecordTimeoutRecovery", recovery)

      config = ::RSpec::Core::Configuration.new
      config.expect_with :rspec
      config.disable_monkey_patching!
      described_class.install_example_timeout!(config, seconds: 0.01)

      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)

      original_world = ::RSpec.world
      ::RSpec.world = ::RSpec::Core::World.new(config)
      expect(
        ::RSpec.describe("timeout recovery probe") do
          it "raises after timeout" do
            expect { raise "should not run" }.not_to raise_error
          end
        end.run
      ).to be(false)
      expect(recovery).to have_received(:disconnect_all_connection_pools!)
    ensure
      ::RSpec.world = original_world if defined?(original_world)
    end

    it "does not disconnect ActiveRecord pools when an example fails for other reasons" do
      recovery = class_double(
        "Polyrun::RSpec::ActiveRecordTimeoutRecovery",
        disconnect_all_connection_pools!: nil
      )
      stub_const("Polyrun::RSpec::ActiveRecordTimeoutRecovery", recovery)

      config = ::RSpec::Core::Configuration.new
      config.expect_with :rspec
      config.disable_monkey_patching!
      described_class.install_example_timeout!(config, seconds: 5)

      original_world = ::RSpec.world
      ::RSpec.world = ::RSpec::Core::World.new(config)
      expect(
        ::RSpec.describe("non-timeout failure probe") do
          it "fails normally" do
            expect(true).to be(false), "example failure"
          end
        end.run
      ).to be(false)
      expect(recovery).not_to have_received(:disconnect_all_connection_pools!)
    ensure
      ::RSpec.world = original_world if defined?(original_world)
    end

    it "does not register per-example timeouts while example debug is enabled" do
      ENV["POLYRUN_EXAMPLE_DEBUG"] = "1"
      config = ::RSpec::Core::Configuration.new
      config.expect_with :rspec
      config.disable_monkey_patching!
      described_class.install_example_timeout!(config, seconds: 0.01)

      original_world = ::RSpec.world
      ::RSpec.world = ::RSpec::Core::World.new(config)
      expect(
        ::RSpec.describe("timeout probe") do
          it "sleeps without timing out" do
            started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            sleep 0.05
            elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
            expect(elapsed).to be >= 0.05
          end
        end.run
      ).to be(true)
    ensure
      ::RSpec.world = original_world if defined?(original_world)
    end
  end
end
