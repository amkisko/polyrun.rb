require "spec_helper"
require "polyrun/rspec/sharded_formatter_compat"

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
