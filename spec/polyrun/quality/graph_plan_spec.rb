require "spec_helper"
require "polyrun/graph/plan"
require "fileutils"
require "json"
require "digest"

RSpec.describe Polyrun::Graph::Plan do
  around do |example|
    Dir.mktmpdir do |root|
      @root = root
      @directory = File.join(root, ".polyrun/graph/plans/p123")
      FileUtils.mkdir_p(File.join(@directory, "tree/lib"))
      FileUtils.mkdir_p(File.join(root, "lib"))
      %w[a b].each do |name|
        File.write(File.join(root, "lib/#{name}.rb"), "original #{name}")
        File.write(File.join(@directory, "tree/lib/#{name}.rb"), "changed #{name}")
      end
      @meta = {"pre_hashes" => %w[a b].to_h { |name| ["lib/#{name}.rb", Digest::SHA256.file(File.join(root, "lib/#{name}.rb")).hexdigest] }, "operations" => []}
      File.write(File.join(@directory, "meta.json"), JSON.generate(@meta))
      File.write(File.join(@directory, "check.json"), JSON.generate("status" => "ok"))
      @plan = described_class.new(root, "p123")
      example.run
    end
  end

  it "binds successful check to staged bytes and metadata" do
    expect { @plan.verify! }.to raise_error(Polyrun::Graph::Error, /check/)
    @plan.record_check!
    expect(@plan.verify!).to be_truthy
    File.write(File.join(@directory, "tree/lib/a.rb"), "tampered")
    expect { @plan.verify! }.to raise_error(Polyrun::Graph::Error, /changed/)
  end

  it "checks every original file before permitting any source write" do
    @plan.record_check!
    File.write(File.join(@root, "lib/b.rb"), "concurrent change")
    expect { @plan.verify! }.to raise_error(Polyrun::Graph::Error, /lib\/b.rb/)
    expect(File.read(File.join(@root, "lib/a.rb"))).to eq("original a")
  end

  it "invalidates both check artifacts before another prove" do
    @plan.record_check!
    @plan.invalidate!
    expect { @plan.verify! }.to raise_error(Polyrun::Graph::Error)
    expect(File.exist?(File.join(@directory, "check.json"))).to be(false)
  end

  it "rejects unsafe plan identifiers and symlink state directories" do
    ["../p123", "/tmp/p123", "p/123", ""].each do |id|
      expect { described_class.new(@root, id) }.to raise_error(Polyrun::Graph::Error)
    end
    File.symlink(@root, File.join(@directory, "tree/escape"))
    expect { @plan.record_check! }.to raise_error(Polyrun::Graph::Error, /symbolic/)
  end

  it "rejects escaping metadata paths even with a valid check" do
    @meta["pre_hashes"]["../escape.rb"] = "fake"
    File.write(File.join(@directory, "meta.json"), JSON.generate(@meta))
    expect { @plan.record_check! }.to raise_error(Polyrun::Graph::Error, /path/)
  end

  it "refuses a check with a missing staged original" do
    File.unlink(File.join(@directory, "tree/lib/b.rb"))
    expect { @plan.record_check! }.to raise_error(Polyrun::Graph::Error, /missing/)
  end
end
