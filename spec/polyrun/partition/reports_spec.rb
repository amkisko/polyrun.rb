require "spec_helper"

RSpec.describe "Polyrun partition reporting" do
  describe Polyrun::Partition::Reports do
    let(:costs) { {"a" => 10.0, "b" => 4.0, "c" => 4.0} }
    let(:plan) do
      Polyrun::Partition::Plan.new(
        items: %w[a b c],
        total_shards: 2,
        strategy: "cost_binpack",
        costs: costs
      )
    end

    it "computes imbalance metrics" do
      m = described_class.imbalance_metrics(plan.shard_weight_totals)
      expect(m[:max_shard_seconds]).to eq(10.0)
      expect(m[:min_shard_seconds]).to eq(8.0)
      expect(m[:avg_shard_seconds]).to eq(9.0)
      expect(m[:imbalance_ratio]).to be_within(0.01).of(10.0 / 9.0)
      expect(m[:slowest_shard]).to eq(0)
    end

    it "finds dominant files above target shard time" do
      candidates = described_class.dominant_candidates(plan)
      expect(candidates.map { |c| c[:path] }).to include("a")
      expect(candidates.first[:multiple]).to be > 1.0
    end
  end

  describe Polyrun::Partition::TimingDiagnostics do
    it "reports missing files and coverage" do
      root = Dir.pwd
      a = File.expand_path("a.rb", root)
      b = File.expand_path("b.rb", root)
      costs = {a => 1.0}
      analysis = described_class.analyze(
        items: [a, b],
        costs: costs,
        timing_path: nil,
        root: root,
        granularity: :file
      )
      expect(analysis[:known_files]).to eq(1)
      expect(analysis[:total_files]).to eq(2)
      expect(analysis[:coverage]).to eq(0.5)
      expect(analysis[:missing_files].size).to eq(1)
    end

    it "reports example-level coverage using path:line keys" do
      root = Dir.pwd
      a1 = File.expand_path("a.rb", root) + ":1"
      a2 = File.expand_path("a.rb", root) + ":2"
      b1 = File.expand_path("b.rb", root) + ":1"
      costs = {a1 => 1.0}
      analysis = described_class.analyze(
        items: [a1, a2, b1],
        costs: costs,
        timing_path: nil,
        root: root,
        granularity: :example
      )
      expect(analysis[:known_files]).to eq(2)
      expect(analysis[:total_files]).to eq(3)
      expect(analysis[:missing_files]).to eq([b1])
    end
  end
end
