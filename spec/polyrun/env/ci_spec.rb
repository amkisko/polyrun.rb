require "spec_helper"

RSpec.describe Polyrun::Env::Ci do
  around do |ex|
    old = ENV.to_h
    ex.run
    ENV.replace(old)
  end

  it "detects GitLab parallel index" do
    ENV["GITLAB_CI"] = "true"
    ENV["CI"] = "true"
    ENV["CI_NODE_INDEX"] = "3"
    ENV["CI_NODE_TOTAL"] = "8"
    expect(described_class.detect_shard_index).to eq(3)
    expect(described_class.detect_shard_total).to eq(8)
  end

  it "detects CI_NODE_* when CI is set without GitLab (e.g. user-mapped vars on any CI)" do
    ENV.delete("GITLAB_CI")
    ENV["CI"] = "true"
    ENV["GITHUB_ACTIONS"] = "true"
    ENV["CI_NODE_INDEX"] = "2"
    ENV["CI_NODE_TOTAL"] = "5"
    expect(described_class.detect_shard_index).to eq(2)
    expect(described_class.detect_shard_total).to eq(5)
  end

  it "prefers POLYRUN_SHARD_INDEX over CI" do
    ENV["POLYRUN_SHARD_INDEX"] = "1"
    ENV["CI_NODE_INDEX"] = "3"
    expect(described_class.detect_shard_index).to eq(1)
  end
end
