require "spec_helper"
require "json"
require "tmpdir"

RSpec.describe Polyrun::Timing::Merge do
  describe ".merge_files" do
    it "merges disjoint paths" do
      Dir.mktmpdir do |dir|
        a = File.join(dir, "a.json")
        b = File.join(dir, "b.json")
        File.write(a, JSON.dump({"/a.rb" => 1.0}))
        File.write(b, JSON.dump({"/b.rb" => 2.0}))
        m = described_class.merge_files([a, b])
        expect(m).to eq({"/a.rb" => 1.0, "/b.rb" => 2.0})
      end
    end

    it "merges path:line example keys with max seconds" do
      Dir.mktmpdir do |dir|
        a = File.join(dir, "a.json")
        b = File.join(dir, "b.json")
        File.write(a, JSON.dump({"/app/x_spec.rb:10" => 1.0}))
        File.write(b, JSON.dump({"/app/x_spec.rb:10" => 2.0, "/app/y_spec.rb:1" => 0.5}))
        m = described_class.merge_files([a, b])
        expect(m["/app/x_spec.rb:10"]).to eq(2.0)
        expect(m["/app/y_spec.rb:1"]).to eq(0.5)
      end
    end

    it "takes max seconds when the same path appears in multiple fragments" do
      Dir.mktmpdir do |dir|
        a = File.join(dir, "a.json")
        b = File.join(dir, "b.json")
        File.write(a, JSON.dump({"/x.rb" => 1.0, "/y.rb" => 3.0}))
        File.write(b, JSON.dump({"/x.rb" => 2.5, "/z.rb" => 0.5}))
        m = described_class.merge_files([a, b])
        expect(m["/x.rb"]).to eq(2.5)
        expect(m["/y.rb"]).to eq(3.0)
        expect(m["/z.rb"]).to eq(0.5)
      end
    end

    it "ignores non-hash JSON roots" do
      Dir.mktmpdir do |dir|
        bad = File.join(dir, "bad.json")
        good = File.join(dir, "good.json")
        File.write(bad, JSON.dump([1, 2, 3]))
        File.write(good, JSON.dump({"/a.rb" => 1.0}))
        m = described_class.merge_files([bad, good])
        expect(m).to eq({"/a.rb" => 1.0})
      end
    end
  end

  describe ".merge_and_write" do
    it "writes pretty JSON" do
      Dir.mktmpdir do |dir|
        f = File.join(dir, "t.json")
        File.write(f, JSON.dump({"/a.rb" => 1.0}))
        out = File.join(dir, "out.json")
        described_class.merge_and_write([f], out)
        expect(JSON.parse(File.read(out))).to eq({"/a.rb" => 1.0})
        expect(File.read(out)).to include("\n") # pretty_generate
      end
    end
  end
end
