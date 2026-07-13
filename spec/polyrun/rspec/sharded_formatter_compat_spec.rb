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

    it "silences BaseTextFormatter seed, summary, and pending under POLYRUN_SHARD_TOTAL" do
      require "rspec/core/formatters/progress_formatter"
      formatter = ::RSpec::Core::Formatters::ProgressFormatter.new(StringIO.new)
      ENV["POLYRUN_SHARD_TOTAL"] = "2"
      described_class.install!
      expect(::RSpec::Core::Formatters::BaseTextFormatter.ancestors).to include(described_class::TextFormatterSilencer)
      seed_notification = instance_double("SeedNotification", seed_used?: true, fully_formatted: "Randomized with seed 1")
      summary_notification = instance_double("SummaryNotification", fully_formatted: "1 example, 0 failures")
      pending_notification = instance_double("PendingNotification", pending_examples: [double], fully_formatted_pending_examples: "Pending:")
      expect { formatter.seed(seed_notification) }.not_to output.to_stdout
      expect { formatter.dump_summary(summary_notification) }.not_to output.to_stdout
      expect { formatter.dump_pending(pending_notification) }.not_to output.to_stdout
    end

    it "noops Fuubar seed announcements when Fuubar is loaded" do
      fuubar_class = Class.new do
        def seed(_notification)
          raise "seed should be replaced"
        end
      end
      stub_const("Fuubar", fuubar_class)
      formatter = Fuubar.new
      ENV["POLYRUN_SHARD_TOTAL"] = "2"
      described_class.install!
      expect(Fuubar.ancestors).to include(described_class::FuubarSeedSilencer)
      expect { formatter.seed(nil) }.not_to raise_error
    end
  end
end
