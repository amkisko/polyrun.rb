require "spec_helper"
require "json"
require "fileutils"

RSpec.describe "optional quality tool configuration" do
  around do |example|
    Dir.mktmpdir do |root|
      @root = root
      @config = File.join(root, "polyrun.yml")
      FileUtils.mkdir_p(File.join(root, "lib"))
      File.write(File.join(root, "lib/account.rb"), "class Account; def self.value; 2; end; end")
      File.write(File.join(root, "probe.rb"), "require 'account'; abort unless Account.value == 2")
      example.run
    end
  end

  def configure(data)
    File.write(@config, data.to_yaml)
  end

  def run_tool(*arguments)
    polyrun("--config", @config, *arguments)
  end

  it "keeps graph and mutation disabled until explicitly enabled without creating graph state" do
    configure({})
    output, status = run_tool("graph", "index", "--root", @root, "--json")
    expect(status.exitstatus).to eq(2)
    expect(JSON.parse(output)["code"]).to eq("FEATURE_DISABLED")
    expect(File.exist?(File.join(@root, ".polyrun"))).to be(false)
    output, status = run_tool("mutate", "--root", @root, "--subject", "Account.value", "--", Gem.ruby, "probe.rb")
    expect(status.exitstatus).to eq(2)
    expect(output).to include("disabled")
    output, status = run_tool("graph", "index", "--enable", "--root", @root, "--json")
    expect(status.exitstatus).to eq(0), output
    configure("graph" => {"enabled" => true, "root" => @root})
    output, status = polyrun("--config", @config, "graph", "index", "--json", "--no-enable", env: {"POLYRUN_GRAPH" => "1"})
    expect(status.exitstatus).to eq(2)
    expect(JSON.parse(output)["code"]).to eq("FEATURE_DISABLED")
  end

  it "shares root worker defaults with existing workers and lets feature and CLI settings override them" do
    configure("workers" => 2, "timeout" => 0.01, "mutation" => {"enabled" => true, "root" => @root,
                                                                "timeout" => 2, "subjects" => ["Account.value"], "command" => [Gem.ruby, "-Ilib", "probe.rb"], "operators" => ["literal"]})
    output, status = run_tool("config", "workers")
    expect(status.exitstatus).to eq(0)
    expect(output.strip).to eq("2")
    output, status = run_tool("mutate")
    expect(status.exitstatus).to eq(0), output
    expect(JSON.parse(output)).to include("mutations" => 3, "killed" => 3)
    output, status = run_tool("mutate", "--timeout", "0.001")
    expect(status.exitstatus).to eq(1)
    expect(JSON.parse(output)["code"]).to eq("BASELINE_FAILED")
  end

  it "uses a configured graph state directory, source roots, and resource bounds" do
    FileUtils.mkdir_p(File.join(@root, "src"))
    File.write(File.join(@root, "src/other.rb"), "class Other; def call; true; end; end")
    configure("root" => @root, "graph" => {"enabled" => true, "state_dir" => "graph-state", "source_roots" => ["src"], "max_nodes" => 1})
    output, status = run_tool("graph", "index", "--json")
    expect(status.exitstatus).to eq(0), output
    expect(File).to exist(File.join(@root, "graph-state/index.json"))
    output, status = run_tool("graph", "inspect", "Account.value", "--json")
    expect(status.exitstatus).to eq(1)
    expect(JSON.parse(output)["code"]).to eq("UNKNOWN_TARGET")
    File.write(File.join(@root, "src/more.rb"), "class More; def call; true; end; end")
    output, status = run_tool("graph", "index", "--json")
    expect(status.exitstatus).to eq(1)
    expect(JSON.parse(output)["code"]).to eq("RESOURCE_LIMIT")
  end

  it "configures quality subcommands and refuses malformed or unknown settings" do
    configure("root" => @root, "quality" => {"measure" => {"enabled" => true, "label" => "configured", "command" => [Gem.ruby, "-e", "puts 'ready'"]}})
    output, status = run_tool("measure")
    expect(status.exitstatus).to eq(0), output
    expect(JSON.parse(output)).to include("label" => "configured", "stdout" => "ready\n")
    configure("graph" => {"enabled" => "false", "max_nods" => 12})
    output, status = run_tool("validate")
    expect(status.exitstatus).to eq(1)
    expect(output).to include("graph.enabled", "graph.max_nods")
  end

  it "applies suite overlays and exposes the effective tool settings" do
    configure("timeout" => 30, "graph" => {"enabled" => false}, "suites" => {"review" => {"graph" => {"enabled" => true, "timeout" => 3}}})
    output, status = polyrun("--config", @config, "--suite", "review", "config", "graph")
    expect(status.exitstatus).to eq(0), output
    expect(JSON.parse(output)).to include("enabled" => true, "timeout" => 3, "state_dir" => ".polyrun/graph")
  end

  it "applies a tighter graph node ceiling even when the source snapshot is cached" do
    settings = {"enabled" => true, "root" => @root, "max_nodes" => 10}
    File.write(File.join(@root, "lib/account.rb"), "class Account; def first; true; end; def second; false; end; end")
    configure("graph" => settings)
    output, status = run_tool("graph", "index", "--json")
    expect(status.exitstatus).to eq(0), output
    configure("graph" => settings.merge("max_nodes" => 1))
    output, status = run_tool("graph", "index", "--json")
    expect(status.exitstatus).to eq(1)
    expect(JSON.parse(output)["code"]).to eq("RESOURCE_LIMIT")
  end

  it "uses a configured prove command only for checks across the complete graph workflow" do
    File.write(File.join(@root, "lib/account.rb"), "class Account; def self.value; helper; end; def self.helper; 2; end; def self.replacement; 3; end; end")
    configure("graph" => {"enabled" => true, "root" => @root, "state_dir" => "graph-state", "json" => true, "prove" => true,
                          "command" => [Gem.ruby, "-Ilib", "-raccount", "-e", "abort unless Account.value == 3"]})
    output, status = run_tool("graph", "index")
    expect(status.exitstatus).to eq(0), output
    snapshot = JSON.parse(output).fetch("snapshot")
    output, status = run_tool("graph", "inspect", "Account.value", "--calls")
    expect(status.exitstatus).to eq(0), output
    node = JSON.parse(output).fetch("nodes").first.fetch("calls").first
    change = {"snapshot" => snapshot, "operations" => [{"op" => "replace_call_name", "node" => node["id"],
                                                        "expect" => node.slice("name", "fingerprint"), "replacement" => "replacement"}]}
    File.write(File.join(@root, "change.json"), JSON.generate(change))
    output, status = run_tool("graph", "plan", File.join(@root, "change.json"))
    expect(status.exitstatus).to eq(0), output
    plan = JSON.parse(output).fetch("plan_id")
    %w[check apply].each do |verb|
      output, status = run_tool("graph", verb, plan)
      expect(status.exitstatus).to eq(0), output
    end
  end

  it "writes graph output to the configured report destination" do
    destination = File.join(@root, "graph-report.json")
    configure("graph" => {"enabled" => true, "root" => @root, "json" => true, "output" => destination})
    output, status = run_tool("graph", "index")
    expect(status.exitstatus).to eq(0), output
    expect(File).to exist(destination)
    expect(JSON.parse(File.read(destination))).to eq(JSON.parse(output))
  end

  it "rejects feature settings that have no effect on that feature" do
    configure("quality" => {"measure" => {"source_roots" => ["lib"]}})
    output, status = run_tool("validate")
    expect(status.exitstatus).to eq(1)
    expect(output).to include("quality.measure.source_roots")
  end
end
