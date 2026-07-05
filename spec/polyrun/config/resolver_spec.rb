require "spec_helper"

RSpec.describe Polyrun::Config::Resolver do
  describe ".merged_prepare_env" do
    it "merges yaml env over process env for duplicate keys" do
      prep = {"env" => {"FOO" => "from_yaml"}}
      env = {"FOO" => "from_env", "BAR" => "only_env"}
      merged = described_class.merged_prepare_env(prep, env)
      expect(merged["FOO"]).to eq("from_yaml")
      expect(merged["BAR"]).to eq("only_env")
    end
  end

  describe ".resolve_shard_index" do
    it "uses POLYRUN_SHARD_INDEX when set" do
      pc = {"shard_index" => 9}
      env = {"POLYRUN_SHARD_INDEX" => "3"}
      expect(described_class.resolve_shard_index(pc, env)).to eq(3)
    end

    it "falls back to partition yaml" do
      pc = {"shard_index" => 2}
      env = {}
      expect(described_class.resolve_shard_index(pc, env)).to eq(2)
    end
  end

  describe ".parallel_worker_count_default" do
    it "uses POLYRUN_WORKERS when set" do
      env = {"POLYRUN_WORKERS" => "7"}
      expect(described_class.parallel_worker_count_default(env)).to eq(7)
    end

    it "falls back to Config::DEFAULT_PARALLEL_WORKERS" do
      env = {}
      expect(described_class.parallel_worker_count_default(env)).to eq(Polyrun::Config::DEFAULT_PARALLEL_WORKERS)
    end
  end

  describe ".resolve_shard_processes" do
    it "uses POLYRUN_SHARD_PROCESSES when set" do
      pc = {"shard_processes" => 9}
      env = {"POLYRUN_SHARD_PROCESSES" => "4"}
      expect(described_class.resolve_shard_processes(pc, env)).to eq(4)
    end

    it "falls back to partition yaml" do
      pc = {"shard_processes" => 3}
      env = {}
      expect(described_class.resolve_shard_processes(pc, env)).to eq(3)
    end

    it "defaults to 1" do
      expect(described_class.resolve_shard_processes({}, {})).to eq(1)
    end
  end

  describe ".resolve_partition_timing_granularity" do
    it "defaults to file" do
      expect(described_class.resolve_partition_timing_granularity({}, nil, {})).to eq(:file)
    end

    it "reads POLYRUN_TIMING_GRANULARITY when config and CLI omit" do
      env = {"POLYRUN_TIMING_GRANULARITY" => "example"}
      expect(described_class.resolve_partition_timing_granularity({}, nil, env)).to eq(:example)
    end

    it "uses partition.timing_granularity from YAML when CLI is nil" do
      pc = {"timing_granularity" => "example"}
      expect(described_class.resolve_partition_timing_granularity(pc, nil, {})).to eq(:example)
    end

    it "prefers explicit CLI value over YAML partition" do
      pc = {"timing_granularity" => "example"}
      expect(described_class.resolve_partition_timing_granularity(pc, "file", {})).to eq(:file)
    end

    it "prefers explicit CLI value over POLYRUN_TIMING_GRANULARITY" do
      env = {"POLYRUN_TIMING_GRANULARITY" => "example"}
      expect(described_class.resolve_partition_timing_granularity({}, "file", env)).to eq(:file)
    end
  end
end
