require "spec_helper"

RSpec.describe Polyrun::Partition::Hrw do
  let(:salt) { "polyrun-hrw" }

  it "weighted_shard_for matches shard_for with uniform shard weights" do
    %w[a b c d e].each do |path|
      u = described_class.shard_for(path: path, total_shards: 5, seed: salt)
      w = described_class.weighted_shard_for(path: path, total_shards: 5, seed: salt)
      expect(w).to eq(u)
    end
  end

  it "weighted_shard_for can differ from shard_for with heterogeneous shard weights" do
    path = "spec/file_0_spec.rb"
    u = described_class.shard_for(path: path, total_shards: 3, seed: salt)
    w = described_class.weighted_shard_for(path: path, total_shards: 3, seed: salt, shard_weights: [10.0, 1.0, 1.0])
    expect(w).not_to eq(u)
  end

  it "POLYRUN_HRW_FAST_SCORE uses faster scoring while staying deterministic" do
    path = "spec/a_spec.rb"
    default_score = described_class.send(:score, path, 0, salt)
    ENV["POLYRUN_HRW_FAST_SCORE"] = "1"
    fast_score = described_class.send(:score, path, 0, salt)
    expect(fast_score).not_to eq(default_score)
    expect(described_class.shard_for(path: path, total_shards: 5, seed: salt)).to eq(
      described_class.shard_for(path: path, total_shards: 5, seed: salt)
    )
  ensure
    ENV.delete("POLYRUN_HRW_FAST_SCORE")
  end
end
