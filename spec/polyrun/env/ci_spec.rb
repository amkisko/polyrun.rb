require "spec_helper"

RSpec.describe Polyrun::Env::Ci do
  around do |ex|
    old = ENV.to_h
    # run-shards sets POLYRUN_SHARD_*; clear so CI env examples are isolated.
    ENV.delete("POLYRUN_SHARD_INDEX")
    ENV.delete("POLYRUN_SHARD_TOTAL")
    ex.run
    ENV.replace(old)
  end

  it "detects CI_NODE_* index and total when CI is set" do
    ENV["CI"] = "true"
    ENV["CI_NODE_INDEX"] = "3"
    ENV["CI_NODE_TOTAL"] = "8"
    expect(described_class.detect_shard_index).to eq(3)
    expect(described_class.detect_shard_total).to eq(8)
  end

  it "reads parallel job index env when CI is set" do
    ENV["CI"] = "true"
    ENV["BUILDKITE_PARALLEL_JOB"] = "4"
    expect(described_class.detect_shard_index).to eq(4)
  end

  it "reads alternate parallel index/total env when CI is set" do
    ENV["CI"] = "true"
    ENV["CIRCLE_NODE_INDEX"] = "1"
    ENV["CIRCLE_NODE_TOTAL"] = "4"
    expect(described_class.detect_shard_index).to eq(1)
    expect(described_class.detect_shard_total).to eq(4)
  end

  it "prefers POLYRUN_SHARD_INDEX over CI" do
    ENV["POLYRUN_SHARD_INDEX"] = "1"
    ENV["CI_NODE_INDEX"] = "3"
    expect(described_class.detect_shard_index).to eq(1)
  end

  describe ".polyrun_env" do
    it "returns POLYRUN_ENV when set" do
      ENV["POLYRUN_ENV"] = "staging"
      ENV["CI"] = "true"
      expect(described_class.polyrun_env).to eq("staging")
    end

    it "returns ci when CI is truthy" do
      ENV.delete("POLYRUN_ENV")
      ENV["CI"] = "true"
      expect(described_class.polyrun_env).to eq("ci")
    end

    it "returns local when CI is unset" do
      ENV.delete("POLYRUN_ENV")
      ENV.delete("CI")
      expect(described_class.polyrun_env).to eq("local")
    end
  end
end
