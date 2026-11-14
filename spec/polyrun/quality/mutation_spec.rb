require "spec_helper"
require "polyrun/mutation/runner"
require "fileutils"

RSpec.describe Polyrun::Mutation::Runner do
  around do |example|
    Dir.mktmpdir do |root|
      @root = root
      FileUtils.mkdir_p(File.join(root, "lib"))
      File.write(File.join(root, "lib/account.rb"), "class Account; def self.value; 2; end; def self.other; 3; end; end")
      @command = [Gem.ruby, "-Ilib", "-raccount", "-e", "abort 'wrong' unless Account.value == 2 && Account.other == 3"]
      example.run
    end
  end

  it "deduplicates and deterministically shards explicit subjects" do
    result = described_class.new(root: @root, arguments: @command).call(["Account.value", "Account.other", "Account.other"], shard: 1, total: 2)
    expect(result["subjects"]).to eq(["Account.other"])
    expect(result).to include("ok" => true, "survived" => 0)
    expect(result["killed"]).to be > 0
  end

  it "allows an empty CI shard without executing a baseline" do
    result = described_class.new(root: @root).call(["Account.value"], shard: 2, total: 2)
    expect(result).to include("ok" => true, "mutations" => 0, "baseline" => nil)
  end

  it "rejects malformed subjects, missing test commands, and unsafe worker bounds" do
    runner = described_class.new(root: @root)
    expect { runner.call(["--help"]) }.to raise_error(ArgumentError)
    expect { runner.call([]) }.to raise_error(ArgumentError)
    expect { runner.call(["Account.value"]) }.to raise_error(ArgumentError, /test command/)
    expect { runner.call(["Account.value"], shard: 0) }.to raise_error(ArgumentError)
    expect { described_class.new(root: @root, workers: 0) }.to raise_error(ArgumentError)
  end

  it "bounds retained diagnostics and refuses to call truncated results complete" do
    command = [Gem.ruby, "-Ilib", "-raccount", "-e", "puts 'x' * 800; abort unless Account.value == 2"]
    result = described_class.new(root: @root, arguments: command, max_report_bytes: 1000).call(["Account.value"])
    expect(result["ok"]).to be(false)
    expect(result["results"].map { |row| row["code"] }).to include("REPORT_LIMIT")
    expect(result["killed"]).to be_nil
  end

  it "rejects a mutation ladder beyond the requested bound before running tests" do
    runner = described_class.new(root: @root, arguments: @command, max_mutations: 1)
    expect { runner.call(["Account.value"]) }.to raise_error(ArgumentError, /mutation limit/)
  end

  it "tests the return contract of an empty method" do
    File.open(File.join(@root, "lib/account.rb"), "a") { |file| file.puts("\nclass Account; def self.empty; end; end") }
    command = [Gem.ruby, "-Ilib", "-raccount", "-e", "abort unless Account.empty.nil?"]
    report = described_class.new(root: @root, arguments: command).call(["Account.empty"])
    expect(report).to include("ok" => true, "survived" => 0)
    expect(report["killed"]).to be > 0
  end
end
