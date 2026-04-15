require "spec_helper"
require "tmpdir"

RSpec.describe Polyrun::Config::Effective do
  describe ".build" do
    it "overlays partition shard fields and workers" do
      Dir.mktmpdir do |dir|
        with_chdir(dir) do
          File.write("polyrun.yml", <<~YAML)
            partition:
              paths_file: spec/list.txt
              shard_total: 5
            prepare:
              recipe: default
          YAML
          cfg = Polyrun::Config.load(path: File.join(dir, "polyrun.yml"))
          env = {
            "POLYRUN_SHARD_INDEX" => "1",
            "POLYRUN_SHARD_TOTAL" => "5",
            "POLYRUN_WORKERS" => "3",
            "POLYRUN_SHARD_PROCESSES" => "4"
          }
          h = described_class.build(cfg, env: env)
          expect(h["partition"]["paths_file"]).to eq("spec/list.txt")
          expect(h["partition"]["shard_index"]).to eq(1)
          expect(h["partition"]["shard_total"]).to eq(5)
          expect(h["partition"]["shard_processes"]).to eq(4)
          expect(h["workers"]).to eq(3)
        end
      end
    end
  end

  describe ".dig" do
    it "resolves dotted paths on the effective tree" do
      Dir.mktmpdir do |dir|
        with_chdir(dir) do
          File.write("polyrun.yml", "version: 1\n")
          cfg = Polyrun::Config.load(path: File.join(dir, "polyrun.yml"))
          expect(described_class.dig(cfg, "version")).to eq(1)
          expect(described_class.dig(cfg, "partition.nope")).to be_nil
        end
      end
    end
  end
end
