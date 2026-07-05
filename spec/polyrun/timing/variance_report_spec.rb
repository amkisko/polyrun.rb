require "spec_helper"

RSpec.describe Polyrun::Timing::VarianceReport do
  describe ".analyze" do
    it "flags high variance when p95 exceeds twice the mean" do
      stats = {
        "a.rb" => {"mean" => 1.0, "p95" => 2.5, "runs" => 5, "failures" => 0, "timeouts" => 0, "last_seconds" => 1.0}
      }
      flags = described_class.analyze(stats)
      expect(flags).to include(hash_including(path: "a.rb", kind: "high_variance"))
    end

    it "flags often_failed when failure rate exceeds 30 percent with at least three runs" do
      stats = {
        "b.rb" => {"mean" => 1.0, "p95" => 1.0, "runs" => 4, "failures" => 2, "timeouts" => 0, "last_seconds" => 1.0}
      }
      flags = described_class.analyze(stats)
      expect(flags).to include(hash_including(path: "b.rb", kind: "often_failed"))
    end

    it "flags timeout_cluster when timeouts reach two" do
      stats = {
        "c.rb" => {"mean" => 1.0, "p95" => 1.0, "runs" => 2, "failures" => 0, "timeouts" => 2, "last_seconds" => 1.0}
      }
      flags = described_class.analyze(stats)
      expect(flags).to include(hash_including(path: "c.rb", kind: "timeout_cluster"))
    end

    it "flags runtime_regression when last run exceeds twice the mean" do
      stats = {
        "d.rb" => {"mean" => 2.0, "p95" => 2.0, "runs" => 5, "failures" => 0, "timeouts" => 0, "last_seconds" => 5.0}
      }
      flags = described_class.analyze(stats)
      expect(flags).to include(hash_including(path: "d.rb", kind: "runtime_regression"))
    end

    it "skips entries with fewer than two runs" do
      stats = {"e.rb" => 3.0}
      expect(described_class.analyze(stats)).to eq([])
    end
  end

  describe ".format_report" do
    it "lists analyzed flags and reports none when empty" do
      text = described_class.format_report({})
      expect(text).to include("Polyrun timing variance report")
      expect(text).to include("(none)")
    end
  end

  describe ".emit_warnings!" do
    it "writes a warning per flag" do
      stats = {
        "f.rb" => {"mean" => 1.0, "p95" => 3.0, "runs" => 3, "failures" => 0, "timeouts" => 0, "last_seconds" => 1.0}
      }
      expect(Polyrun::Log).to receive(:warn).with(/high_variance.*f\.rb/)
      described_class.emit_warnings!(stats)
    end
  end
end
