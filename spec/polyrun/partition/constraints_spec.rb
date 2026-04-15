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
  end
end
