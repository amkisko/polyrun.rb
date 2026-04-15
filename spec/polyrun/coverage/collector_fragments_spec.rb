require "spec_helper"

RSpec.describe Polyrun::Coverage::Collector do
  describe ".finish_debug_time_label" do
    around do |example|
      old = ENV.to_h
      example.run
      ENV.replace(old)
    end

    it "includes matrix shard and local worker when POLYRUN_SHARD_MATRIX_TOTAL > 1" do
      ENV["POLYRUN_SHARD_MATRIX_TOTAL"] = "3"
      ENV["POLYRUN_SHARD_MATRIX_INDEX"] = "1"
      ENV["POLYRUN_SHARD_INDEX"] = "2"
      ENV["POLYRUN_SHARD_TOTAL"] = "4"
      expect(described_class.finish_debug_time_label).to include("shard(matrix)=1")
      expect(described_class.finish_debug_time_label).to include("worker(local)=2")
    end

    it "mentions worker-only when multiple local shards without matrix" do
      ENV.delete("POLYRUN_SHARD_MATRIX_TOTAL")
      ENV["POLYRUN_SHARD_TOTAL"] = "3"
      ENV["POLYRUN_SHARD_INDEX"] = "1"
      expect(described_class.finish_debug_time_label).to include("worker=1")
    end
  end

  describe ".build_meta" do
    it "includes fragment keys when cfg has fragment_meta" do
      cfg = {
        root: "/tmp/proj",
        fragment_meta: {
          basename: "shard0-worker1",
          worker_index: "1",
          shard_matrix_index: "0"
        }
      }
      m = described_class.build_meta(cfg)
      expect(m["polyrun_fragment_basename"]).to eq("shard0-worker1")
      expect(m["polyrun_worker_index"]).to eq("1")
      expect(m["polyrun_shard_matrix_index"]).to eq("0")
    end

    it "omits matrix keys when shard_matrix_index is nil" do
      cfg = {
        root: "/tmp/proj",
        fragment_meta: {
          basename: "worker2",
          worker_index: "2",
          shard_matrix_index: nil
        }
      }
      m = described_class.build_meta(cfg)
      expect(m["polyrun_fragment_basename"]).to eq("worker2")
      expect(m["polyrun_worker_index"]).to eq("2")
      expect(m).not_to have_key("polyrun_shard_matrix_index")
    end
  end

  describe ".fragment_default_basename_from_env" do
    it "uses shard<M>-worker<W> when matrix total > 1" do
      env = {
        "POLYRUN_SHARD_MATRIX_TOTAL" => "5",
        "POLYRUN_SHARD_MATRIX_INDEX" => "2",
        "POLYRUN_SHARD_INDEX" => "3",
        "POLYRUN_SHARD_TOTAL" => "4"
      }
      expect(described_class.fragment_default_basename_from_env(env)).to eq("shard2-worker3")
    end

    it "uses worker<W> when multiple local workers and no matrix" do
      env = {
        "POLYRUN_SHARD_INDEX" => "2",
        "POLYRUN_SHARD_TOTAL" => "5"
      }
      expect(described_class.fragment_default_basename_from_env(env)).to eq("worker2")
    end

    it "uses numeric index for a single process" do
      env = {
        "POLYRUN_SHARD_INDEX" => "0",
        "POLYRUN_SHARD_TOTAL" => "1"
      }
      expect(described_class.fragment_default_basename_from_env(env)).to eq("0")
    end
  end
end
