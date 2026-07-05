require "spec_helper"
require "fileutils"

RSpec.describe Polyrun::Partition::Constraints do
  describe "#forced_shard_for" do
    it "matches pin to a plain file path" do
      Dir.mktmpdir do |dir|
        abs = File.join(dir, "a.rb")
        c = described_class.new(pin_map: {abs => 1}, root: dir)
        expect(c.forced_shard_for(abs)).to eq(1)
      end
    end

    it "matches pin to the file part of a path:line locator (experimental example items)" do
      Dir.mktmpdir do |dir|
        abs = File.join(dir, "heavy_spec.rb")
        c = described_class.new(pin_map: {abs => 0}, root: dir)
        expect(c.forced_shard_for("#{abs}:42")).to eq(0)
      end
    end

    it "matches pin glob against the file part of a path:line locator" do
      Dir.mktmpdir do |dir|
        sys = File.join(dir, "spec", "system", "x_spec.rb")
        FileUtils.mkdir_p(File.dirname(sys))
        File.write(sys, "")
        c = described_class.new(pin_map: {"**/x_spec.rb" => 0}, root: dir)
        expect(c.forced_shard_for("#{sys}:10")).to eq(0)
      end
    end

    it "forces serial_glob paths to serial_shard" do
      Dir.mktmpdir do |dir|
        sys = File.join(dir, "spec", "system", "x_spec.rb")
        FileUtils.mkdir_p(File.dirname(sys))
        File.write(sys, "")
        c = described_class.new(serial_globs: ["**/system/**"], root: dir)
        expect(c.forced_shard_for("spec/system/x_spec.rb")).to eq(0)
      end
    end

    it "uses custom serial_shard index" do
      c = described_class.new(serial_globs: ["**/slow/**"], serial_shard: 3, root: Dir.pwd)
      expect(c.forced_shard_for("spec/slow/x_spec.rb")).to eq(3)
    end

    it "any? is false for empty constraints" do
      expect(described_class.new(root: Dir.pwd).any?).to be false
    end

    it "any? is true when pins exist" do
      c = described_class.new(pin_map: {"a.rb" => 1}, root: Dir.pwd)
      expect(c.any?).to be true
    end
  end

  describe ".from_hash" do
    it "returns empty constraints for non-hash input" do
      expect(described_class.from_hash(nil).any?).to be false
    end

    it "loads pins and serial globs from yaml-shaped hash" do
      c = described_class.from_hash(
        {"pin" => {"a.rb" => 2}, "serial_glob" => ["**/slow/**"], "serial_shard" => 1},
        root: Dir.pwd
      )
      expect(c.any?).to be true
      expect(c.forced_shard_for("a.rb")).to eq(2)
    end
  end
end
