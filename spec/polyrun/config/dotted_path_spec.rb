require "spec_helper"

RSpec.describe Polyrun::Config::DottedPath do
  describe ".dig" do
    let(:tree) do
      {
        "partition" => {
          "paths_file" => "spec/spec_paths.txt",
          shard_index: 1
        },
        "workers" => 4
      }
    end

    it "reads nested string keys" do
      expect(described_class.dig(tree, "partition.paths_file")).to eq("spec/spec_paths.txt")
    end

    it "reads nested symbol keys via string segments" do
      expect(described_class.dig(tree, "partition.shard_index")).to eq(1)
    end

    it "returns nil for missing paths" do
      expect(described_class.dig(tree, "partition.missing")).to be_nil
      expect(described_class.dig(tree, "missing.child")).to be_nil
    end

    it "returns nil when a segment is empty" do
      expect(described_class.dig(tree, "partition..paths_file")).to be_nil
      expect(described_class.dig(tree, ".partition")).to be_nil
    end

    it "returns nil for empty dotted path" do
      expect(described_class.dig(tree, "")).to be_nil
    end

    it "returns nil when an intermediate value is not a hash" do
      expect(described_class.dig(tree, "workers.child")).to be_nil
    end
  end
end
