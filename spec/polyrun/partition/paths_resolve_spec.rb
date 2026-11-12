require "spec_helper"
require "fileutils"

RSpec.describe Polyrun::Partition::Paths do
  describe ".resolve_run_shard_items" do
    it "reads an explicit paths_file" do
      Dir.mktmpdir do |dir|
        list = File.join(dir, "paths.txt")
        File.write(list, "a.rb\n\nb.rb\n")
        r = described_class.resolve_run_shard_items(paths_file: list, cwd: dir, partition: {})
        expect(r[:items]).to eq(%w[a.rb b.rb])
        expect(r[:source]).to eq(list)
      end
    end

    it "errors when paths_file is missing" do
      Dir.mktmpdir do |dir|
        missing = File.join(dir, "missing.txt")
        r = described_class.resolve_run_shard_items(paths_file: missing, cwd: dir, partition: {})
        expect(r[:error]).to include("paths file not found")
      end
    end

    it "uses legacy spec/spec_paths.txt for auto/rspec when present" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "spec"))
        File.write(File.join(dir, "spec", "spec_paths.txt"), "spec/legacy_spec.rb\n")
        File.write(File.join(dir, "spec", "a_spec.rb"), "")
        r = described_class.resolve_run_shard_items(paths_file: nil, cwd: dir, partition: {"suite" => "auto"})
        expect(r[:items]).to eq(["spec/legacy_spec.rb"])
        expect(r[:source]).to eq("spec/spec_paths.txt")
      end
    end

    it "globs rspec files when partition.suite is rspec" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "spec"))
        path = File.join(dir, "spec", "a_spec.rb")
        File.write(path, "")
        r = described_class.resolve_run_shard_items(paths_file: nil, cwd: dir, partition: {"suite" => "rspec"})
        expect(r[:items]).to eq([path])
        expect(r[:source]).to include("spec")
      end
    end

    it "errors when partition.suite is rspec but no spec files exist" do
      Dir.mktmpdir do |dir|
        r = described_class.resolve_run_shard_items(paths_file: nil, cwd: dir, partition: {suite: "rspec"})
        expect(r[:error]).to include("rspec")
      end
    end

    it "errors when partition.suite is minitest but no test files exist" do
      Dir.mktmpdir do |dir|
        r = described_class.resolve_run_shard_items(paths_file: nil, cwd: dir, partition: {"suite" => "minitest"})
        expect(r[:error]).to include("minitest")
      end
    end

    it "errors when partition.suite is sus but no test/**/*.rb files exist" do
      Dir.mktmpdir do |dir|
        r = described_class.resolve_run_shard_items(paths_file: nil, cwd: dir, partition: {"suite" => "sus"})
        expect(r[:error]).to include("sus")
      end
    end

    it "globs Polyrun quick files when partition.suite is quick" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "spec", "polyrun_quick"))
        path = File.join(dir, "spec", "polyrun_quick", "a.rb")
        File.write(path, "")
        r = described_class.resolve_run_shard_items(paths_file: nil, cwd: dir, partition: {"suite" => "quick"})
        expect(r[:items]).to eq([path])
        expect(r[:source]).to include("quick")
      end
    end

    it "errors when partition.suite is quick but no quick files exist" do
      Dir.mktmpdir do |dir|
        r = described_class.resolve_run_shard_items(paths_file: nil, cwd: dir, partition: {"suite" => "quick"})
        expect(r[:error]).to include("quick")
      end
    end

    it "auto-picks spec files when present" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "spec"))
        path = File.join(dir, "spec", "a_spec.rb")
        File.write(path, "")
        r = described_class.resolve_run_shard_items(paths_file: nil, cwd: dir, partition: {"suite" => ""})
        expect(r[:items]).to eq([path])
        expect(r[:source]).to include("spec")
      end
    end

    it "auto-picks sus when config/sus.rb and test/**/*.rb exist without specs" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "config"))
        FileUtils.mkdir_p(File.join(dir, "test", "demo"))
        File.write(File.join(dir, "config", "sus.rb"), "# sus\n")
        path = File.join(dir, "test", "demo", "thing.rb")
        File.write(path, "")
        r = described_class.resolve_run_shard_items(paths_file: nil, cwd: dir, partition: {})
        expect(r[:items]).to eq([path])
        expect(r[:source]).to include("sus")
      end
    end

    it "auto-picks minitest when only test/**/*_test.rb exist" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "test"))
        path = File.join(dir, "test", "a_test.rb")
        File.write(path, "")
        r = described_class.resolve_run_shard_items(paths_file: nil, cwd: dir, partition: {"suite" => "auto"})
        expect(r[:items]).to eq([path])
        expect(r[:source]).to include("test")
      end
    end

    it "auto-picks quick files when only Polyrun quick files exist" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "spec", "polyrun_quick"))
        path = File.join(dir, "spec", "polyrun_quick", "a.rb")
        File.write(path, "")
        r = described_class.resolve_run_shard_items(paths_file: nil, cwd: dir, partition: {})
        expect(r[:items]).to eq([path])
        expect(r[:source]).to include("quick")
      end
    end

    it "errors on auto when no suite files exist" do
      Dir.mktmpdir do |dir|
        r = described_class.resolve_run_shard_items(paths_file: nil, cwd: dir, partition: {})
        expect(r[:error]).to include("no spec paths")
      end
    end

    it "errors on unknown partition.suite" do
      Dir.mktmpdir do |dir|
        r = described_class.resolve_run_shard_items(paths_file: nil, cwd: dir, partition: {"suite" => "nose"})
        expect(r[:error]).to include("unknown partition.suite")
      end
    end
  end

  describe ".detect_auto_suite" do
    it "returns :quick when only Polyrun quick files exist" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "spec", "polyrun_quick"))
        File.write(File.join(dir, "spec", "polyrun_quick", "a.rb"), "")
        expect(described_class.detect_auto_suite(dir)).to eq(:quick)
      end
    end
  end
end
