# rubocop:disable Polyrun/FileLength -- collector behavior matrix
require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Polyrun::Coverage::Collector do
  describe ".run_formatter_per_worker?" do
    around do |example|
      old_total = ENV["POLYRUN_SHARD_TOTAL"]
      old_wf = ENV["POLYRUN_COVERAGE_WORKER_FORMATS"]
      example.run
      old_total ? ENV.store("POLYRUN_SHARD_TOTAL", old_total) : ENV.delete("POLYRUN_SHARD_TOTAL")
      old_wf ? ENV.store("POLYRUN_COVERAGE_WORKER_FORMATS", old_wf) : ENV.delete("POLYRUN_COVERAGE_WORKER_FORMATS")
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
        "/project/lib" => {"lines" => [1]},
        "/project/spec/b.rb" => {"lines" => [1]},
        "/other/lib/c.rb" => {"lines" => [1]}
      }
      out = described_class.keep_under_root(blob, root, ["lib"])
      expect(out.keys).to eq(["/project/lib/a.rb", "/project/lib"])
    end

    it "returns the blob unchanged when track_under is nil or empty" do
      blob = {"/project/lib/a.rb" => {"lines" => [1]}}
      expect(described_class.keep_under_root(blob, "/project", nil)).to eq(blob)
      expect(described_class.keep_under_root(blob, "/project", [])).to eq(blob)
    end
  end

  describe ".normalize_blob_paths" do
    it "expands relative paths against root" do
      root = "/project"
      blob = {"lib/a.rb" => {"lines" => [1]}}
      out = described_class.normalize_blob_paths(blob, root)
      expect(out.keys).to eq(["/project/lib/a.rb"])
    end
  end

  describe ".normalize_groups" do
    it "returns nil for nil or empty groups" do
      expect(described_class.normalize_groups(nil)).to be_nil
      expect(described_class.normalize_groups({})).to be_nil
      expect(described_class.normalize_groups([])).to be_nil
    end

    it "stringifies keys and values for a hash" do
      expect(described_class.normalize_groups(Lib: "{lib}/**/*.rb")).to eq(
        "Lib" => "{lib}/**/*.rb"
      )
    end
  end

  describe ".result_to_blob string keys" do
    it "accepts string lines and branches keys" do
      br = [{"type" => "if", "coverage" => 1}]
      raw = {"/x.rb" => {"lines" => [nil, 1], "branches" => br}}
      blob = described_class.result_to_blob(raw)
      expect(blob["/x.rb"]["lines"]).to eq([nil, 1])
      expect(blob["/x.rb"]["branches"]).to eq(br)
    end

    it "skips hashes without a lines array" do
      raw = {"/x.rb" => {"branches" => []}}
      expect(described_class.result_to_blob(raw)).to eq({})
    end
  end

  describe "track_files finish contract (collector finish path)" do
    it "merges untracked files for non-sharded runs" do
      Dir.mktmpdir do |root|
        app_file = File.join(root, "app", "models", "loaded.rb")
        unloaded_file = File.join(root, "app", "models", "unloaded.rb")
        FileUtils.mkdir_p(File.dirname(app_file))
        File.write(app_file, "class Loaded; end\n")
        File.write(unloaded_file, "class Unloaded; end\n")

        blob = {
          app_file => {"lines" => [nil, 1]},
          "/ruby/stdlib/forwardable.rb" => {"lines" => [nil, 1]}
        }
        filtered = Polyrun::Coverage::TrackFiles.keep_tracked_files(blob, root, "app/**/*.rb")
        out = Polyrun::Coverage::TrackFiles.merge_untracked_into_blob(filtered, root, "app/**/*.rb")

        expect(out.keys.sort).to eq([app_file, unloaded_file].sort)
        expect(out[app_file]["lines"]).to eq([nil, 1])
        expect(out[unloaded_file]["lines"]).to eq([0])
      end
    end

    it "keeps loaded files matched by track_files even when track_under differs for non-sharded runs" do
      Dir.mktmpdir do |root|
        app_file = File.join(root, "app", "models", "loaded.rb")
        lib_file = File.join(root, "lib", "loaded.rb")
        FileUtils.mkdir_p(File.dirname(app_file))
        FileUtils.mkdir_p(File.dirname(lib_file))
        File.write(app_file, "class AppLoaded; end\n")
        File.write(lib_file, "class LibLoaded; end\n")

        blob = {
          app_file => {"lines" => [nil, 1]},
          lib_file => {"lines" => [nil, 3]}
        }
        filtered = Polyrun::Coverage::TrackFiles.keep_tracked_files(blob, root, "{app,lib}/**/*.rb")
        out = Polyrun::Coverage::TrackFiles.merge_untracked_into_blob(filtered, root, "{app,lib}/**/*.rb")

        expect(out.keys.sort).to eq([app_file, lib_file].sort)
        expect(out[lib_file]["lines"]).to eq([nil, 3])
      end
    end

    it "keeps only loaded tracked files for sharded runs without merging untracked" do
      Dir.mktmpdir do |root|
        app_file = File.join(root, "app", "models", "loaded.rb")
        lib_file = File.join(root, "lib", "loaded.rb")
        unloaded_file = File.join(root, "lib", "unloaded.rb")
        FileUtils.mkdir_p(File.dirname(app_file))
        FileUtils.mkdir_p(File.dirname(lib_file))
        File.write(app_file, "class AppLoaded; end\n")
        File.write(lib_file, "class LibLoaded; end\n")
        File.write(unloaded_file, "class Unloaded; end\n")

        blob = {
          app_file => {"lines" => [nil, 1]},
          lib_file => {"lines" => [nil, 3]}
        }
        out = Polyrun::Coverage::TrackFiles.keep_tracked_files(blob, root, "{app,lib}/**/*.rb")

        expect(out.keys.sort).to eq([app_file, lib_file].sort)
        expect(out[lib_file]["lines"]).to eq([nil, 3])
        expect(out).not_to have_key(unloaded_file)
      end
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

  describe ".coverage_requested_for_quick?" do
    around do |example|
      old_cov = ENV["POLYRUN_COVERAGE"]
      old_dis = ENV["POLYRUN_COVERAGE_DISABLE"]
      old_simple = ENV["SIMPLECOV_DISABLE"]
      old_covered = ENV["COVERAGE"]
      example.run
      if old_cov
        ENV["POLYRUN_COVERAGE"] = old_cov
      else
        ENV.delete("POLYRUN_COVERAGE")
      end
      if old_dis
        ENV["POLYRUN_COVERAGE_DISABLE"] = old_dis
      else
        ENV.delete("POLYRUN_COVERAGE_DISABLE")
      end
      if old_simple
        ENV["SIMPLECOV_DISABLE"] = old_simple
      else
        ENV.delete("SIMPLECOV_DISABLE")
      end
      if old_covered
        ENV["COVERAGE"] = old_covered
      else
        ENV.delete("COVERAGE")
      end
    end

    it "is false when disabled" do
      ENV["POLYRUN_COVERAGE"] = "1"
      ENV["POLYRUN_COVERAGE_DISABLE"] = "1"
      expect(described_class.coverage_requested_for_quick?(Dir.pwd)).to be false
    end

    it "is false when SIMPLECOV_DISABLE=1" do
      ENV["POLYRUN_COVERAGE"] = "1"
      ENV.delete("POLYRUN_COVERAGE_DISABLE")
      ENV["SIMPLECOV_DISABLE"] = "1"
      expect(described_class.coverage_requested_for_quick?(Dir.pwd)).to be false
    end

    it "is true when POLYRUN_COVERAGE=1" do
      ENV["POLYRUN_COVERAGE"] = "1"
      ENV.delete("POLYRUN_COVERAGE_DISABLE")
      expect(described_class.coverage_requested_for_quick?(Dir.pwd)).to be true
    end

    it "is true when COVERAGE is set to a Covered report name" do
      ENV.delete("POLYRUN_COVERAGE")
      ENV.delete("POLYRUN_COVERAGE_DISABLE")
      ENV["COVERAGE"] = "PartialSummary"
      expect(described_class.coverage_requested_for_quick?(Dir.pwd)).to be true
    end

    it "is false when COVERAGE is a falsey token" do
      ENV.delete("POLYRUN_COVERAGE")
      ENV.delete("POLYRUN_COVERAGE_DISABLE")
      ENV["COVERAGE"] = "false"
      expect(described_class.coverage_requested_for_quick?(Dir.pwd)).to be false
    end

    it "is true when config/polyrun_coverage.yml exists and POLYRUN_QUICK_COVERAGE=1" do
      ENV.delete("POLYRUN_COVERAGE")
      ENV.delete("POLYRUN_COVERAGE_DISABLE")
      ENV.delete("COVERAGE")
      ENV["POLYRUN_QUICK_COVERAGE"] = "1"
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "config"))
        File.write(File.join(dir, "config", "polyrun_coverage.yml"), "{}\n")
        expect(described_class.coverage_requested_for_quick?(dir)).to be true
      end
    ensure
      ENV.delete("POLYRUN_QUICK_COVERAGE")
    end

    it "is false when only config file exists (use POLYRUN_QUICK_COVERAGE=1 to opt in)" do
      ENV.delete("POLYRUN_COVERAGE")
      ENV.delete("POLYRUN_COVERAGE_DISABLE")
      ENV.delete("POLYRUN_QUICK_COVERAGE")
      ENV.delete("COVERAGE")
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "config"))
        File.write(File.join(dir, "config", "polyrun_coverage.yml"), "{}\n")
        expect(described_class.coverage_requested_for_quick?(dir)).to be false
      end
    end

    it "is false when unset and no config file" do
      ENV.delete("POLYRUN_COVERAGE")
      ENV.delete("POLYRUN_COVERAGE_DISABLE")
      ENV.delete("COVERAGE")
      Dir.mktmpdir do |dir|
        expect(described_class.coverage_requested_for_quick?(dir)).to be false
      end
    end
  end

  describe ".start!" do
    def with_saved_collector_config
      had_config = described_class.instance_variable_defined?(:@config)
      saved = had_config ? described_class.instance_variable_get(:@config) : nil
      yield
    ensure
      if had_config
        described_class.instance_variable_set(:@config, saved)
      elsif described_class.instance_variable_defined?(:@config)
        described_class.remove_instance_variable(:@config)
      end
    end

    around do |example|
      old_dis = ENV["POLYRUN_COVERAGE_DISABLE"]
      old_simple = ENV["SIMPLECOV_DISABLE"]
      ENV.delete("POLYRUN_COVERAGE_DISABLE")
      ENV.delete("SIMPLECOV_DISABLE")
      example.run
    ensure
      old_dis ? ENV.store("POLYRUN_COVERAGE_DISABLE", old_dis) : ENV.delete("POLYRUN_COVERAGE_DISABLE")
      old_simple ? ENV.store("SIMPLECOV_DISABLE", old_simple) : ENV.delete("SIMPLECOV_DISABLE")
    end

    it "defaults strict to true when a minimum is set and starts Coverage when idle" do
      Dir.mktmpdir do |dir|
        with_saved_collector_config do
          allow(Coverage).to receive(:running?).and_return(false)
          allow(Coverage).to receive(:start)
          described_class.start!(root: dir, minimum_line_percent: 80, track_under: ["lib"])
          expect(Coverage).to have_received(:start).with(lines: true, branches: false)
          cfg = described_class.instance_variable_get(:@config)
          expect(cfg[:strict]).to be true
          expect(cfg[:minimum_line_percent]).to eq(80)
          expect(described_class).to be_started
        end
      end
    end

    it "sets strict false when no minimum is given" do
      Dir.mktmpdir do |dir|
        with_saved_collector_config do
          allow(Coverage).to receive(:running?).and_return(true)
          described_class.start!(root: dir, track_under: ["lib"])
          cfg = described_class.instance_variable_get(:@config)
          expect(cfg[:strict]).to be false
          expect(cfg[:minimum_line_percent]).to be_nil
        end
      end
    end

    it "honors strict: false when a minimum is set" do
      Dir.mktmpdir do |dir|
        with_saved_collector_config do
          allow(Coverage).to receive(:running?).and_return(true)
          described_class.start!(root: dir, minimum_line_percent: 50, strict: false)
          expect(described_class.instance_variable_get(:@config)[:strict]).to be false
        end
      end
    end

    it "is a no-op when coverage is disabled" do
      with_saved_collector_config do
        ENV["POLYRUN_COVERAGE_DISABLE"] = "1"
        described_class.remove_instance_variable(:@config) if described_class.instance_variable_defined?(:@config)
        described_class.start!(root: Dir.pwd, minimum_line_percent: 99)
        expect(described_class.instance_variable_defined?(:@config) && described_class.instance_variable_get(:@config)).to be_falsy
      end
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
end
# rubocop:enable Polyrun/FileLength
