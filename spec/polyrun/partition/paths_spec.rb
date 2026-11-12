require "spec_helper"
require "fileutils"

RSpec.describe Polyrun::Partition::Paths do
  describe ".detect_auto_suite" do
    it "returns :rspec when spec files exist" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "spec"))
        File.write(File.join(dir, "spec", "a_spec.rb"), "")
        expect(described_class.detect_auto_suite(dir)).to eq(:rspec)
      end
    end

    it "returns :minitest when only test files exist" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "test"))
        File.write(File.join(dir, "test", "a_test.rb"), "")
        expect(described_class.detect_auto_suite(dir)).to eq(:minitest)
      end
    end

    it "returns :sus when config/sus.rb and test/**/*.rb exist" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "config"))
        FileUtils.mkdir_p(File.join(dir, "test", "demo"))
        File.write(File.join(dir, "config", "sus.rb"), "# sus\n")
        File.write(File.join(dir, "test", "demo", "thing.rb"), "")
        expect(described_class.detect_auto_suite(dir)).to eq(:sus)
      end
    end

    it "prefers :sus over :minitest when config/sus.rb is present" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "config"))
        FileUtils.mkdir_p(File.join(dir, "test"))
        File.write(File.join(dir, "config", "sus.rb"), "# sus\n")
        File.write(File.join(dir, "test", "a_test.rb"), "")
        expect(described_class.detect_auto_suite(dir)).to eq(:sus)
      end
    end

    it "returns nil when empty" do
      Dir.mktmpdir do |dir|
        expect(described_class.detect_auto_suite(dir)).to be_nil
      end
    end
  end

  describe ".infer_suite_from_paths" do
    it "detects rspec, minitest, sus, and quick" do
      Dir.mktmpdir do |dir|
        a = File.join(dir, "a_spec.rb")
        b = File.join(dir, "b_test.rb")
        s = File.join(dir, "test", "demo", "thing.rb")
        q = File.join(dir, "quick.rb")
        FileUtils.mkdir_p(File.dirname(s))
        File.write(a, "")
        File.write(b, "")
        File.write(s, "")
        File.write(q, "")
        expect(described_class.infer_suite_from_paths([a])).to eq(:rspec)
        expect(described_class.infer_suite_from_paths([b])).to eq(:minitest)
        expect(described_class.infer_suite_from_paths([s])).to eq(:sus)
        expect(described_class.infer_suite_from_paths([q])).to eq(:quick)
      end
    end

    it "classifies polyrun_quick paths as quick even under test/" do
      Dir.mktmpdir do |dir|
        q = File.join(dir, "test", "polyrun_quick", "a.rb")
        FileUtils.mkdir_p(File.dirname(q))
        File.write(q, "")
        expect(described_class.infer_suite_from_paths([q])).to eq(:quick)
      end
    end

    it "strips path:line locators before classifying" do
      expect(described_class.infer_suite_from_paths(["spec/a_spec.rb:1"])).to eq(:rspec)
      expect(described_class.infer_suite_from_paths(["test/b_test.rb:12"])).to eq(:minitest)
      expect(described_class.infer_suite_from_paths(["test/demo/thing.rb:3"])).to eq(:sus)
      expect(described_class.infer_suite_from_paths(["spec/a_spec.rb:1:2"])).to eq(:rspec)
    end

    it "returns :invalid when mixing spec and test" do
      Dir.mktmpdir do |dir|
        a = File.join(dir, "a_spec.rb")
        b = File.join(dir, "b_test.rb")
        File.write(a, "")
        File.write(b, "")
        expect(described_class.infer_suite_from_paths([a, b])).to eq(:invalid)
      end
    end

    it "returns :invalid when mixing sus and minitest path families" do
      Dir.mktmpdir do |dir|
        s = File.join(dir, "test", "demo", "thing.rb")
        t = File.join(dir, "test", "a_test.rb")
        FileUtils.mkdir_p(File.dirname(s))
        File.write(s, "")
        File.write(t, "")
        expect(described_class.infer_suite_from_paths([s, t])).to eq(:invalid)
      end
    end
  end

  describe ".resolve_run_shard_items" do
    it "uses test glob when partition.suite is minitest" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "test"))
        File.write(File.join(dir, "test", "t_test.rb"), "")
        r = described_class.resolve_run_shard_items(paths_file: nil, cwd: dir, partition: {"suite" => "minitest"})
        expect(r[:items]).to eq([File.join(dir, "test", "t_test.rb")])
        expect(r[:source]).to include("test")
      end
    end

    it "uses test/**/*.rb glob when partition.suite is sus" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "test", "demo"))
        path = File.join(dir, "test", "demo", "thing.rb")
        File.write(path, "")
        r = described_class.resolve_run_shard_items(paths_file: nil, cwd: dir, partition: {"suite" => "sus"})
        expect(r[:items]).to eq([path])
        expect(r[:source]).to include("sus")
      end
    end

    it "skips legacy spec/spec_paths.txt when partition.suite is minitest" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "spec"))
        FileUtils.mkdir_p(File.join(dir, "test"))
        File.write(File.join(dir, "spec", "a_spec.rb"), "")
        File.write(File.join(dir, "spec", "spec_paths.txt"), "spec/a_spec.rb\n")
        test = File.join(dir, "test", "t_test.rb")
        File.write(test, "")

        r = described_class.resolve_run_shard_items(
          paths_file: nil,
          cwd: dir,
          partition: {"suite" => "minitest"}
        )
        expect(r[:items]).to eq([test])
        expect(r[:source]).to include("test")
      end
    end

    it "skips legacy spec/spec_paths.txt when partition.suite is sus" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "spec"))
        FileUtils.mkdir_p(File.join(dir, "test", "demo"))
        File.write(File.join(dir, "spec", "spec_paths.txt"), "spec/a_spec.rb\n")
        path = File.join(dir, "test", "demo", "thing.rb")
        File.write(path, "")

        r = described_class.resolve_run_shard_items(
          paths_file: nil,
          cwd: dir,
          partition: {"suite" => "sus"}
        )
        expect(r[:items]).to eq([path])
        expect(r[:source]).to include("sus")
      end
    end
  end
end
