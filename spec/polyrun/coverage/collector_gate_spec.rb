require "spec_helper"
require "open3"
require "tmpdir"

RSpec.describe "Polyrun::Coverage::Collector minimum_line_percent gate" do
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
