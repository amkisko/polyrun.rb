require "spec_helper"
require "polyrun/graph/client"
require "polyrun/graph/planner"
require "fileutils"
require "json"

RSpec.describe Polyrun::Graph::Client do
  around do |example|
    Dir.mktmpdir do |root|
      @root = root
      FileUtils.mkdir_p(File.join(root, "lib"))
      File.write(File.join(root, "lib/account.rb"), "class Account; def self.value; helper; end; def self.helper; 1; end; def self.replacement; 2; end; end")
      index = Polyrun::Graph::Index.new(root).call
      call = index["calls"].find { |node| node["name"] == "helper" }
      change = {"snapshot" => index["snapshot"], "operations" => [{"op" => "replace_call_name", "node" => call["id"],
                                                                   "expect" => call.slice("name", "fingerprint"), "replacement" => "replacement"}]}
      File.write(File.join(root, "change.json"), JSON.generate(change))
      @id = Polyrun::Graph::Planner.new(root).call("change.json").fetch("plan_id")
      @client = described_class.new(root: root, timeout: 2)
      example.run
    end
  end

  it "proves the staged source before permitting apply" do
    result = @client.call(["check", @id, "--json"], prove: [Gem.ruby, "-Ilib", "-raccount", "-e", "abort unless Account.value == 2"])
    expect(result["exitstatus"]).to eq(0), result.inspect
    expect(@client.call(["apply", @id, "--json"])["exitstatus"]).to eq(0)
    output, status = Open3.capture2e(Gem.ruby, "-Ilib", "-raccount", "-e", "puts Account.value", chdir: @root)
    expect(status.exitstatus).to eq(0)
    expect(output.strip).to eq("2")
  end

  it "revokes an earlier successful check after failed prove" do
    @client.call(["check", @id])
    expect { @client.call(["check", @id], prove: [Gem.ruby, "-e", "exit 6"]) }.to raise_error(Polyrun::Graph::Error) { |error| expect(error.exitstatus).to eq(6) }
    result = @client.call(["apply", @id, "--json"])
    expect(result["exitstatus"]).to eq(1)
    expect(JSON.parse(result["stderr"])["code"]).to eq("CHECK_FAILED")
  end

  it "refuses approval when a successful prove changes staged source" do
    command = [Gem.ruby, "-e", "File.write('lib/account.rb', 'class Account; def self.value; 99; end; end')"]
    expect { @client.call(["check", @id], prove: command) }.to raise_error(Polyrun::Graph::Error, /changed/)
    result = @client.call(["apply", @id, "--json"])
    expect(result["exitstatus"]).to eq(1)
    output, status = Open3.capture2e(Gem.ruby, "-Ilib", "-raccount", "-e", "puts Account.value", chdir: @root)
    expect(status.exitstatus).to eq(0)
    expect(output.strip).to eq("1")
  end

  it "refuses overlapping graph work without waiting indefinitely" do
    File.open(File.join(@root, ".polyrun/graph/polyrun.lock"), "w") do |lock|
      lock.flock(File::LOCK_EX)
      expect { @client.call(%w[index]) }.to raise_error(Polyrun::Graph::Error, /running/)
    end
  end
end
