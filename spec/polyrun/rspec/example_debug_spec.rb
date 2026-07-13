require "logger"
require "stringio"
require "spec_helper"
require "polyrun/rspec/example_debug"

RSpec.describe Polyrun::RSpec::ExampleDebug do
  describe ".enabled?" do
    around do |example|
      old = ENV["POLYRUN_EXAMPLE_DEBUG"]
      ENV.delete("POLYRUN_EXAMPLE_DEBUG")
      example.run
    ensure
      old.nil? ? ENV.delete("POLYRUN_EXAMPLE_DEBUG") : ENV["POLYRUN_EXAMPLE_DEBUG"] = old
    end

    it "is off unless POLYRUN_EXAMPLE_DEBUG is truthy" do
      expect(described_class.enabled?).to be(false)
      ENV["POLYRUN_EXAMPLE_DEBUG"] = "1"
      expect(described_class.enabled?).to be(true)
    end
  end

  describe ".loggable_sql?" do
    it "skips read-only SQL prefixes" do
      expect(described_class.loggable_sql?("SELECT 1")).to be(false)
      expect(described_class.loggable_sql?("UPDATE users SET x = 1")).to be(true)
    end
  end

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

  describe "feature flags and log levels" do
    around do |example|
      keys = %w[
        POLYRUN_EXAMPLE_DEBUG POLYRUN_DEBUG_SQL DEBUG_SQL POLYRUN_DEBUG_TRACE DEBUG_TRACE
        DEBUG_PROSOPITE DEBUG_PRINT_SPEC DEBUG_LOG_LEVEL
      ]
      old = keys.to_h { |key| [key, ENV[key]] }
      keys.each { |key| ENV.delete(key) }
      example.run
    ensure
      old.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end

    it "enables sql, trace, prosopite, and print helpers only with example debug" do
      ENV["POLYRUN_DEBUG_SQL"] = "1"
      ENV["DEBUG_TRACE"] = "1"
      expect(described_class.sql_enabled?).to be(false)
      expect(described_class.trace_enabled?).to be(false)

      ENV["POLYRUN_EXAMPLE_DEBUG"] = "1"
      expect(described_class.sql_enabled?).to be(true)
      expect(described_class.trace_enabled?).to be(true)
      expect(described_class.example_timeout_disabled?).to be(true)

      ENV["DEBUG_PROSOPITE"] = "1"
      ENV["DEBUG_PRINT_SPEC"] = "1"
      expect(described_class.prosopite_enabled?).to be(true)
      expect(described_class.print_spec_enabled?).to be(true)
    end

    it "maps DEBUG_LOG_LEVEL integers to Ruby Logger severities" do
      ENV["DEBUG_LOG_LEVEL"] = "0"
      expect(described_class.log_level).to eq(Logger::DEBUG)
      expect(described_class.rails_log_level).to eq(:debug)
      ENV["DEBUG_LOG_LEVEL"] = "1"
      expect(described_class.log_level).to eq(Logger::INFO)
      expect(described_class.rails_log_level).to eq(:info)
      ENV["DEBUG_LOG_LEVEL"] = "2"
      expect(described_class.log_level).to eq(Logger::WARN)
      expect(described_class.rails_log_level).to eq(:warn)
      ENV["DEBUG_LOG_LEVEL"] = "3"
      expect(described_class.log_level).to eq(Logger::ERROR)
      expect(described_class.rails_log_level).to eq(:error)
      ENV["DEBUG_LOG_LEVEL"] = "9"
      expect(described_class.log_level).to eq(9)
      expect(described_class.rails_log_level).to eq(:fatal)
    end

    it "maps DEBUG_LOG_LEVEL names to Ruby Logger severities" do
      ENV["DEBUG_LOG_LEVEL"] = "debug"
      expect(described_class.log_level).to eq(Logger::DEBUG)
      expect(described_class.rails_log_level).to eq(:debug)
      ENV["DEBUG_LOG_LEVEL"] = "INFO"
      expect(described_class.log_level).to eq(Logger::INFO)
      expect(described_class.rails_log_level).to eq(:info)
      ENV["DEBUG_LOG_LEVEL"] = " warn "
      expect(described_class.log_level).to eq(Logger::WARN)
      expect(described_class.rails_log_level).to eq(:warn)
      ENV["DEBUG_LOG_LEVEL"] = "error"
      expect(described_class.log_level).to eq(Logger::ERROR)
      expect(described_class.rails_log_level).to eq(:error)
      ENV["DEBUG_LOG_LEVEL"] = "fatal"
      expect(described_class.log_level).to eq(Logger::FATAL)
      expect(described_class.rails_log_level).to eq(:fatal)
    end

    it "falls back to debug when DEBUG_LOG_LEVEL is invalid" do
      ENV["DEBUG_LOG_LEVEL"] = "not-a-level"
      expect(described_class.log_level).to eq(Logger::DEBUG)
      expect(described_class.rails_log_level).to eq(:debug)
    end
  end

  describe ".install_rails_logging!" do
    around do |example|
      keys = %w[POLYRUN_EXAMPLE_DEBUG DEBUG_LOG_LEVEL]
      old = keys.to_h { |key| [key, ENV[key]] }
      keys.each { |key| ENV.delete(key) }
      example.run
    ensure
      old.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end

    it "runs the registered before hook without NameError and applies DEBUG_LOG_LEVEL" do
      ENV["POLYRUN_EXAMPLE_DEBUG"] = "1"
      ENV["DEBUG_LOG_LEVEL"] = "info"

      rails_module = Module.new
      rails_module.define_singleton_method(:logger) { @logger }
      rails_module.define_singleton_method(:logger=) { |value| @logger = value }
      rails_module.logger = Logger.new(StringIO.new)
      stub_const("Rails", rails_module)

      before_hook = nil
      rspec_config = Object.new
      rspec_config.define_singleton_method(:before) { |&block| before_hook = block }

      described_class.install_rails_logging!(rspec_config: rspec_config)

      example = Struct.new(:metadata).new(
        {example_group: {file_path: "spec/probe_spec.rb", line_number: 42}}
      )
      example_group_instance = Object.new

      expect { example_group_instance.instance_exec(example, &before_hook) }.not_to raise_error
      expect(Rails.logger.level).to eq(Logger::INFO)
    end
  end

  describe ".install!" do
    around do |example|
      keys = %w[POLYRUN_EXAMPLE_DEBUG POLYRUN_DEBUG_SQL POLYRUN_DEBUG_TRACE DEBUG_PRINT_SPEC]
      old = keys.to_h { |key| [key, ENV[key]] }
      keys.each { |key| ENV.delete(key) }
      example.run
    ensure
      old.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end

    it "registers trace and path helpers when enabled" do
      config = ::RSpec::Core::Configuration.new
      ENV["POLYRUN_EXAMPLE_DEBUG"] = "1"
      ENV["POLYRUN_DEBUG_TRACE"] = "1"
      ENV["DEBUG_PRINT_SPEC"] = "1"
      expect { described_class.install!(rspec_config: config) }.not_to raise_error
    end
  end
end
