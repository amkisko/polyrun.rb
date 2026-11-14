require "spec_helper"
require "polyrun/graph/transaction"
require "fileutils"
require "json"

RSpec.describe Polyrun::Graph::Transaction do
  around do |example|
    Dir.mktmpdir do |root|
      @root = File.realpath(root)
      @directory = File.join(root, ".polyrun/graph/plans/plan-test")
      FileUtils.mkdir_p(@directory)
      FileUtils.mkdir_p(File.join(root, "lib"))
      File.write(File.join(root, "lib/account.rb"), "original account")
      File.write(File.join(root, "lib/invoice.rb"), "original invoice")
      @transaction = described_class.new(root, @directory)
      @replacements = [["lib/account.rb", "original account", "changed account"], ["lib/invoice.rb", "original invoice", "changed invoice"]]
      example.run
    end
  end

  it "restores earlier writes when a later file cannot be committed" do
    failed = false
    allow(File).to receive(:rename).and_wrap_original do |original, source, target|
      if target == File.join(@root, "lib/invoice.rb") && !failed
        failed = true
        raise Errno::ENOSPC
      end
      original.call(source, target)
    end
    expect { @transaction.commit(@replacements) }.to raise_error(Errno::ENOSPC)
    expect(File.read(File.join(@root, "lib/account.rb"))).to eq("original account")
    expect(File.read(File.join(@root, "lib/invoice.rb"))).to eq("original invoice")
  end

  it "recovers an interrupted apply from its original backups" do
    FileUtils.mkdir_p(File.join(@directory, "backups/lib"))
    files = @replacements.to_h do |relative, before, after|
      File.write(File.join(@directory, "backups", relative), before)
      [relative, {"before" => Digest::SHA256.hexdigest(before), "after" => Digest::SHA256.hexdigest(after)}]
    end
    File.write(File.join(@root, "lib/account.rb"), "changed account")
    File.write(File.join(@directory, "transaction.json"), JSON.generate("state" => "writing", "files" => files))
    expect(@transaction.recover!).to be(true)
    expect(File.read(File.join(@root, "lib/account.rb"))).to eq("original account")
  end

  it "preserves an unrelated edit when interrupted recovery cannot prove ownership" do
    FileUtils.mkdir_p(File.join(@directory, "backups/lib"))
    relative, before, after = @replacements.first
    File.write(File.join(@directory, "backups", relative), before)
    File.write(File.join(@root, relative), "outside edit")
    files = {relative => {"before" => Digest::SHA256.hexdigest(before), "after" => Digest::SHA256.hexdigest(after)}}
    File.write(File.join(@directory, "transaction.json"), JSON.generate("state" => "writing", "files" => files))
    expect { @transaction.recover! }.to raise_error(Polyrun::Graph::Error, /outside/)
    expect(File.read(File.join(@root, relative))).to eq("outside edit")
  end
end
