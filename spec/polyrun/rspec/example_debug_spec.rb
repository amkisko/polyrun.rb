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
    it "registers without error" do
      config = ::RSpec::Core::Configuration.new
      expect { described_class.install_example_timeout!(config, seconds: 5) }.not_to raise_error
    end
  end
end
