require "spec_helper"
require "polyrun/rspec/example_debug"
require "polyrun/rspec/sharded_formatter_compat"

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
    it "registers without error" do
      config = ::RSpec::Core::Configuration.new
      expect { described_class.install_example_timeout!(config, seconds: 5) }.not_to raise_error
    end
  end
end

RSpec.describe Polyrun::RSpec::ShardedFormatterCompat do
  describe ".install!" do
    around do |example|
      old = ENV["POLYRUN_SHARD_TOTAL"]
      ENV.delete("POLYRUN_SHARD_TOTAL")
      example.run
    ensure
      old.nil? ? ENV.delete("POLYRUN_SHARD_TOTAL") : ENV["POLYRUN_SHARD_TOTAL"] = old
    end

    it "is a no-op outside sharded workers" do
      expect { described_class.install! }.not_to change { ::RSpec.configuration.silence_filter_announcements }
    end

    it "silences filter announcements under POLYRUN_SHARD_TOTAL" do
      ENV["POLYRUN_SHARD_TOTAL"] = "4"
      described_class.install!
      expect(::RSpec.configuration.silence_filter_announcements).to be(true)
    end
  end
end
