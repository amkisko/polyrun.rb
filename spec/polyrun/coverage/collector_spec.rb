require "spec_helper"
require "fileutils"
require "open3"
require "tmpdir"

RSpec.describe Polyrun::Coverage::Collector do
  describe ".run_formatter_per_worker?" do
    around do |example|
      old_total = ENV["POLYRUN_SHARD_TOTAL"]
      old_wf = ENV["POLYRUN_COVERAGE_WORKER_FORMATS"]
      example.run
      if old_total
        ENV["POLYRUN_SHARD_TOTAL"] = old_total
      else
        ENV.delete("POLYRUN_SHARD_TOTAL")
      end
      if old_wf
        ENV["POLYRUN_COVERAGE_WORKER_FORMATS"] = old_wf
      else
        ENV.delete("POLYRUN_COVERAGE_WORKER_FORMATS")
      end
    end

    it "is false when multiple shards and worker formats not forced" do
      ENV["POLYRUN_SHARD_TOTAL"] = "5"
      ENV.delete("POLYRUN_COVERAGE_WORKER_FORMATS")
      expect(described_class.run_formatter_per_worker?).to be false
    end

    it "is true for a single shard" do
      ENV["POLYRUN_SHARD_TOTAL"] = "1"
      expect(described_class.run_formatter_per_worker?).to be true
    end

    it "is true when POLYRUN_COVERAGE_WORKER_FORMATS=1 even with multiple shards" do
      ENV["POLYRUN_SHARD_TOTAL"] = "5"
      ENV["POLYRUN_COVERAGE_WORKER_FORMATS"] = "1"
      expect(described_class.run_formatter_per_worker?).to be true
    end
  end

  describe ".keep_under_root" do
    it "keeps only paths under requested directories" do
      root = "/project"
      blob = {
        "/project/lib/a.rb" => {"lines" => [1]},
        "/project/spec/b.rb" => {"lines" => [1]},
        "/other/lib/c.rb" => {"lines" => [1]}
      }
      out = described_class.send(:keep_under_root, blob, root, ["lib"])
      expect(out.keys).to eq(["/project/lib/a.rb"])
    end
  end

  describe ".result_to_blob" do
    it "maps stdlib coverage result to lines-only file entries" do
      raw = {
        "/x.rb" => {lines: [nil, 1, 0]},
        "/skip.rb" => "bad"
      }
      blob = described_class.result_to_blob(raw)
      expect(blob["/x.rb"]["lines"]).to eq([nil, 1, 0])
      expect(blob).not_to have_key("/skip.rb")
    end

    it "preserves branches when present" do
      br = [
        {"type" => "if", "start_line" => 1, "end_line" => 2, "coverage" => 1}
      ]
      raw = {"/x.rb" => {lines: [nil, 1], branches: br}}
      blob = described_class.result_to_blob(raw)
      expect(blob["/x.rb"]["branches"]).to eq(br)
    end
  end

  describe ".branch_coverage_enabled?" do
    around do |example|
      old = ENV["POLYRUN_COVERAGE_BRANCHES"]
      example.run
      if old
        ENV["POLYRUN_COVERAGE_BRANCHES"] = old
      else
        ENV.delete("POLYRUN_COVERAGE_BRANCHES")
      end
    end

    it "is true when POLYRUN_COVERAGE_BRANCHES=1" do
      ENV["POLYRUN_COVERAGE_BRANCHES"] = "1"
      expect(described_class.branch_coverage_enabled?).to be true
    end

    it "is false when unset" do
      ENV.delete("POLYRUN_COVERAGE_BRANCHES")
      expect(described_class.branch_coverage_enabled?).to be false
    end
  end

  describe "minimum_line_percent gate" do
    it "exits 1 when below minimum on a full (single-shard) run" do
      Dir.mktmpdir do |dir|
        lib = File.join(dir, "lib")
        FileUtils.mkdir_p(lib)
        script = <<~RUBY
          $LOAD_PATH.unshift #{File.expand_path("../../lib", __dir__).inspect}
          require "polyrun/coverage/collector"
          ENV.delete("POLYRUN_COVERAGE_DISABLE")
          ENV["POLYRUN_SHARD_TOTAL"] = "1"
          Polyrun::Coverage::Collector.start!(
            root: #{dir.inspect},
            minimum_line_percent: 99,
            track_under: ["lib"]
          )
        RUBY
        _out, status = Open3.capture2e(RbConfig.ruby, "-e", script)
        expect(status.exitstatus).to eq(1)
      end
    end

    it "does not exit on minimum when POLYRUN_SHARD_TOTAL > 1 (per-worker fragment)" do
      Dir.mktmpdir do |dir|
        lib = File.join(dir, "lib")
        FileUtils.mkdir_p(lib)
        script = <<~RUBY
          $LOAD_PATH.unshift #{File.expand_path("../../lib", __dir__).inspect}
          require "polyrun/coverage/collector"
          ENV.delete("POLYRUN_COVERAGE_DISABLE")
          ENV["POLYRUN_SHARD_TOTAL"] = "2"
          Polyrun::Coverage::Collector.start!(
            root: #{dir.inspect},
            minimum_line_percent: 99,
            track_under: ["lib"]
          )
        RUBY
        _out, status = Open3.capture2e(RbConfig.ruby, "-e", script)
        expect(status.exitstatus).to eq(0)
      end
    end
  end
end
