require "spec_helper"
require "json"
require "fileutils"

RSpec.describe "Polyrun graph" do
  around do |example|
    Dir.mktmpdir do |root|
      @root = root
      FileUtils.mkdir_p(File.join(root, "lib"))
      File.write(File.join(root, "lib/account.rb"), "class Account; def value; helper; end; def helper; 1; end; def replacement; 2; end; end")
      example.run
    end
  end

  def graph(*arguments)
    output, status = polyrun("graph", "--enable", *arguments, "--root", @root, "--json")
    [JSON.parse(output), status]
  end

  def make_plan
    index, status = graph("index")
    expect(status.exitstatus).to eq(0)
    inspected, = graph("inspect", "Account#value", "--calls", "--callees")
    call = inspected.fetch("nodes").first.fetch("calls").find { |node| node["name"] == "helper" }
    change = {"snapshot" => index.fetch("snapshot"), "operations" => [{"op" => "replace_call_name", "node" => call.fetch("id"),
                                                                       "expect" => {"name" => "helper", "fingerprint" => call.fetch("fingerprint")}, "replacement" => "replacement"}]}
    File.write(File.join(@root, "change.json"), JSON.generate(change))
    result, status = graph("plan", "change.json")
    expect(status.exitstatus).to eq(0), result.inspect
    result.fetch("plan_id")
  end

  it "indexes, resolves calls, proves, and applies without another executable or source tree" do
    plan = make_plan
    output, status = polyrun("graph", "--enable", "check", plan, "--root", @root, "--json", "--prove", "--", Gem.ruby, "-Ilib", "-raccount", "-e", "abort unless Account.new.value == 2")
    expect(status.exitstatus).to eq(0), output
    result, status = graph("apply", plan)
    expect(status.exitstatus).to eq(0), result.inspect
    output, status = Open3.capture2e(Gem.ruby, "-Ilib", "-raccount", "-e", "puts Account.new.value", chdir: @root)
    expect(status.exitstatus).to eq(0)
    expect(output.strip).to eq("2")
    expect(File).to exist(File.join(@root, ".polyrun/graph/index.json"))
  end

  it "reuses an unchanged snapshot and refuses ambiguous selectors" do
    first, = graph("index")
    second, = graph("index")
    expect(second).to include("snapshot" => first["snapshot"], "reused" => true)
    File.write(File.join(@root, "lib/other.rb"), "class Other; def value; 3; end; end")
    graph("index")
    result, status = graph("inspect", "value")
    expect(status.exitstatus).to eq(1)
    expect(result["code"]).to eq("AMBIGUOUS_NODE")
  end

  it "refuses unchecked, changed staged, and stale source plans before writing" do
    plan = make_plan
    result, status = graph("apply", plan)
    expect(status.exitstatus).to eq(1)
    expect(result["code"]).to eq("CHECK_FAILED")
    graph("check", plan)
    File.write(File.join(@root, "lib/new.rb"), "class Added; end")
    result, status = graph("apply", plan)
    expect(status.exitstatus).to eq(1)
    expect(result["code"]).to eq("STALE_SNAPSHOT")
  end

  it "does not execute indexed source and reports parse errors" do
    File.write(File.join(@root, "lib/side_effect.rb"), 'raise "must not execute"; class SideEffect; def call; true; end; end')
    _, status = graph("index")
    expect(status.exitstatus).to eq(0)
    File.write(File.join(@root, "lib/broken.rb"), "class Broken")
    result, status = graph("index")
    expect(status.exitstatus).to eq(1)
    expect(result["code"]).to eq("PARSE_FAILED")
  end
end
