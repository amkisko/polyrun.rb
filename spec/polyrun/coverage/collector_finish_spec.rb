require "spec_helper"
require "open3"
require "tmpdir"
require "rbconfig"

RSpec.describe "Polyrun::Coverage::Collector finish" do
  it "writes a fragment and applies reject_patterns" do
    Dir.mktmpdir do |dir|
      lib = File.join(dir, "lib", "polyrun")
      FileUtils.mkdir_p(lib)
      kept = File.join(lib, "kept.rb")
      dropped = File.join(lib, "reporting", "rspec_junit.rb")
      FileUtils.mkdir_p(File.dirname(dropped))
      File.write(kept, "def kept\n  1\nend\n")
      File.write(dropped, "def dropped\n  1\nend\n")
      out = File.join(dir, "coverage", "frag.json")
      script = <<~RUBY
        $LOAD_PATH.unshift #{File.expand_path("../../lib", __dir__).inspect}
        require "polyrun/coverage/collector"
        ENV.delete("POLYRUN_COVERAGE_DISABLE")
        ENV["POLYRUN_SHARD_TOTAL"] = "1"
        Polyrun::Coverage::Collector.start!(
          root: #{dir.inspect},
          output_path: #{out.inspect},
          reject_patterns: ["/reporting/rspec_junit.rb"],
          track_under: ["lib"],
          minimum_line_percent: 0,
          strict: false
        )
        load #{kept.inspect}
        load #{dropped.inspect}
      RUBY
      _stdout, status = Open3.capture2e(RbConfig.ruby, "-e", script)
      expect(status.success?).to be true
      payload = JSON.parse(File.read(out))
      paths = (payload["coverage"] || payload).keys
      expect(paths.any? { |p| p.include?("kept.rb") }).to be true
      expect(paths.any? { |p| p.include?("rspec_junit.rb") }).to be false
    end
  end

  it "skips per-worker formatter when POLYRUN_SHARD_TOTAL > 1" do
    Dir.mktmpdir do |dir|
      lib = File.join(dir, "lib")
      FileUtils.mkdir_p(lib)
      File.write(File.join(lib, "x.rb"), "x = 1\n")
      out = File.join(dir, "coverage", "frag.json")
      script = <<~RUBY
        $LOAD_PATH.unshift #{File.expand_path("../../lib", __dir__).inspect}
        require "polyrun/coverage/collector"
        ENV.delete("POLYRUN_COVERAGE_DISABLE")
        ENV["POLYRUN_SHARD_INDEX"] = "0"
        ENV["POLYRUN_SHARD_TOTAL"] = "2"
        Polyrun::Coverage::Collector.start!(
          root: #{dir.inspect},
          output_path: #{out.inspect},
          track_under: ["lib"],
          minimum_line_percent: 0,
          strict: false,
          formatter: Class.new { def format(*) end }
        )
        load File.join(#{dir.inspect}, "lib", "x.rb")
      RUBY
      _stdout, status = Open3.capture2e(RbConfig.ruby, "-e", script)
      expect(status.success?).to be true
      expect(File).to exist(out)
    end
  end

  it "includes group summaries when groups are configured" do
    Dir.mktmpdir do |dir|
      lib = File.join(dir, "lib")
      FileUtils.mkdir_p(lib)
      File.write(File.join(lib, "x.rb"), "x = 1\n")
      out = File.join(dir, "coverage", "frag.json")
      script = <<~RUBY
        $LOAD_PATH.unshift #{File.expand_path("../../lib", __dir__).inspect}
        require "polyrun/coverage/collector"
        ENV.delete("POLYRUN_COVERAGE_DISABLE")
        ENV["POLYRUN_SHARD_TOTAL"] = "1"
        Polyrun::Coverage::Collector.start!(
          root: #{dir.inspect},
          output_path: #{out.inspect},
          track_under: ["lib"],
          track_files: ["lib/**/*.rb"],
          groups: {"Lib" => "lib/**/*.rb"},
          minimum_line_percent: 0,
          strict: false
        )
        load File.join(#{dir.inspect}, "lib", "x.rb")
      RUBY
      _stdout, status = Open3.capture2e(RbConfig.ruby, "-e", script)
      expect(status.success?).to be true
      payload = JSON.parse(File.read(out))
      expect(payload["groups"]).to have_key("Lib")
    end
  end

  it "keeps only tracked files without merging unloaded when sharded" do
    Dir.mktmpdir do |dir|
      lib = File.join(dir, "lib")
      FileUtils.mkdir_p(lib)
      loaded = File.join(lib, "loaded.rb")
      unloaded = File.join(lib, "unloaded.rb")
      File.write(loaded, "x = 1\n")
      File.write(unloaded, "y = 2\n")
      out = File.join(dir, "coverage", "frag.json")
      script = <<~RUBY
        $LOAD_PATH.unshift #{File.expand_path("../../lib", __dir__).inspect}
        require "polyrun/coverage/collector"
        ENV.delete("POLYRUN_COVERAGE_DISABLE")
        ENV["POLYRUN_SHARD_INDEX"] = "0"
        ENV["POLYRUN_SHARD_TOTAL"] = "3"
        Polyrun::Coverage::Collector.start!(
          root: #{dir.inspect},
          output_path: #{out.inspect},
          track_files: ["lib/**/*.rb"],
          minimum_line_percent: 0,
          strict: false
        )
        load #{loaded.inspect}
      RUBY
      _stdout, status = Open3.capture2e(RbConfig.ruby, "-e", script)
      expect(status.success?).to be true
      paths = JSON.parse(File.read(out))["coverage"].keys
      expect(paths.any? { |p| p.include?("loaded.rb") }).to be true
      expect(paths.any? { |p| p.include?("unloaded.rb") }).to be false
    end
  end
end
