require "spec_helper"
require_relative "support/benchmark_profile"

RSpec.describe BenchmarkProfile do
  describe ".output_path" do
    let(:repository_root) { "/tmp/polyrun-benchmarks" }

    it "uses a single commit filename when the working tree is clean" do
      path = described_class.output_path(
        repository_root: repository_root,
        commit_sha: "abc123def456",
        working_tree_clean: true
      )

      expect(path).to eq("/tmp/polyrun-benchmarks/tmp/benchmarks/profile_abc123def456.log")
    end

    it "adds a timestamp when the working tree is dirty" do
      path = described_class.output_path(
        repository_root: repository_root,
        commit_sha: "abc123def456",
        working_tree_clean: false,
        timestamp: "20260713112000"
      )

      expect(path).to eq("/tmp/polyrun-benchmarks/tmp/benchmarks/profile_abc123def456_20260713112000.log")
    end
  end

  describe ".write!" do
    let(:repository_root) { Dir.mktmpdir("polyrun-benchmark-profile") }

    after do
      FileUtils.remove_entry(repository_root)
    end

    it "writes accumulated benchmark lines to the profile file", :aggregate_failures do
      described_class.reset!
      described_class.log("Coverage merge (3 iterations):")
      described_class.log("  merge_two: 0.072s")

      path = described_class.write!(repository_root: repository_root)

      expect(File).to exist(path)
      contents = File.read(path)
      expect(contents).to include("# Benchmark profile")
      expect(contents).to include("Coverage merge (3 iterations):")
      expect(contents).to include("merge_two: 0.072s")
    end
  end
end
