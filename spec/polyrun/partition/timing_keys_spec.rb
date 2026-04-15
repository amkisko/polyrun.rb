require "spec_helper"
require "json"
require "fileutils"

RSpec.describe Polyrun::Partition::TimingKeys do
  describe ".normalize_granularity" do
    it "defaults to file" do
      expect(described_class.normalize_granularity(nil)).to eq(:file)
      expect(described_class.normalize_granularity("")).to eq(:file)
      expect(described_class.normalize_granularity("file")).to eq(:file)
    end

    it "accepts example" do
      expect(described_class.normalize_granularity("example")).to eq(:example)
      expect(described_class.normalize_granularity("EXAMPLES")).to eq(:example)
    end
  end

  describe ".normalize_locator" do
    let(:root) { Dir.pwd }

    it "expands file paths for file granularity" do
      k = described_class.normalize_locator("spec/a_spec.rb", root, :file)
      expect(k).to eq(File.expand_path("spec/a_spec.rb", root))
    end

    it "normalizes path:line for example granularity" do
      k = described_class.normalize_locator("spec/a_spec.rb:42", root, :example)
      expect(k).to eq("#{File.expand_path("spec/a_spec.rb", root)}:42")
    end
  end

  describe ".load_costs_json_file" do
    it "normalizes file keys for file granularity" do
      Dir.mktmpdir do |dir|
        with_chdir(dir) do
          path = File.join(dir, "t.json")
          File.write(path, JSON.dump({"a.rb" => 2.5}))
          h = described_class.load_costs_json_file(path, :file)
          expect(h[File.expand_path("a.rb", Dir.pwd)]).to eq(2.5)
        end
      end
    end

    it "normalizes path:line keys for example granularity" do
      Dir.mktmpdir do |dir|
        with_chdir(dir) do
          ra = File.join(dir, "a.rb")
          rb = File.join(dir, "b.rb")
          path = File.join(dir, "t.json")
          File.write(path, JSON.dump({"#{ra}:1" => 3.0, "#{rb}:2" => 1.0}))
          h = described_class.load_costs_json_file(path, :example)
          root = File.expand_path(Dir.pwd)
          k1 = described_class.normalize_locator("#{ra}:1", root, :example)
          k2 = described_class.normalize_locator("#{rb}:2", root, :example)
          expect(h[k1]).to eq(3.0)
          expect(h[k2]).to eq(1.0)
        end
      end
    end

    it "uses root: for normalizing keys when not the current directory" do
      Dir.mktmpdir do |outer|
        sub = File.join(outer, "repo")
        FileUtils.mkdir_p(sub)
        path = File.join(sub, "t.json")
        File.write(path, JSON.dump({"spec/a.rb" => 2.0}))
        with_chdir(outer) do
          h = described_class.load_costs_json_file(path, :file, root: sub)
          expect(h[File.expand_path("spec/a.rb", sub)]).to eq(2.0)
        end
      end
    end

    it "warns when two keys normalize to the same path with different values" do
      Dir.mktmpdir do |dir|
        with_chdir(dir) do
          path = File.join(dir, "t.json")
          abs = File.expand_path("dup.rb", dir)
          File.write(path, JSON.dump({"dup.rb" => 1.0, abs => 2.0}))
          canon = described_class.normalize_locator("dup.rb", File.expand_path(dir), :file)
          expect(Polyrun::Log).to receive(:warn).with(/duplicate key .*#{Regexp.escape(canon)}/)
          h = described_class.load_costs_json_file(path, :file)
          expect(h[canon]).to eq(2.0)
        end
      end
    end
  end

  describe ".file_part_for_constraint" do
    it "returns file path for path:line" do
      expect(described_class.file_part_for_constraint("spec/a_spec.rb:10")).to eq("spec/a_spec.rb")
    end

    it "returns nil for plain paths" do
      expect(described_class.file_part_for_constraint("spec/a_spec.rb")).to be_nil
    end
  end
end
