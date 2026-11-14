require "spec_helper"
require "polyrun/graph/index"
require "polyrun/quality/sandbox"
require "polyrun/mutation/runner"
require "polyrun/config/tool_validation"
require "fileutils"

RSpec.describe "configurable tool boundaries" do
  around do |example|
    Dir.mktmpdir do |root|
      @root = root
      FileUtils.mkdir_p(File.join(root, "lib"))
      File.write(File.join(root, "lib/account.rb"), "class Account; def self.value; 2; end; end")
      example.run
    end
  end

  it "resolves environment and explicit settings above feature and shared defaults" do
    cfg = Polyrun::Config.new(path: nil, raw: {"workers" => 2, "timeout" => 7, "mutation" => {"workers" => 3}})
    settings = Polyrun::Config::Tools.resolve(cfg, "mutation", root: @root,
      env: {"POLYRUN_WORKERS" => "4", "POLYRUN_TIMEOUT" => "9"}, overrides: {workers: 5})
    expect(settings).to include("enabled" => false, "workers" => 5, "timeout" => 9, "root" => @root)
  end

  it "rejects a non-mapping tool settings value with an explicit mapping diagnostic" do
    expect(Polyrun::Config::ToolValidation.check("nope", Polyrun::Config::ToolDefaults.for("mutation"), "mutation"))
      .to eq(["mutation must be a mapping"])
  end

  it "joins multiple validation diagnostics with a stable separator" do
    cfg = Polyrun::Config.new(path: nil, raw: {"mutation" => {"enabled" => "false", "max_nods" => 1}})
    expect { Polyrun::Config::Tools.resolve(cfg, "mutation", env: {}, root: @root) }
      .to raise_error(ArgumentError, /invalid setting mutation.enabled; unknown setting mutation.max_nods/)
  end

  it "keeps the existing quoted top-level worker shortcut usable by the new tools" do
    cfg = Polyrun::Config.new(path: nil, raw: {"workers" => "2"})
    expect(Polyrun::Config::Tools.resolve(cfg, "mutation", env: {}, root: @root)["workers"]).to eq(2)
  end

  it "rejects invalid new shared defaults before ordinary worker execution" do
    cfg = Polyrun::Config.new(path: nil, raw: {"workers" => "invalid"})
    expect { Polyrun::Config::Resolver.parallel_worker_count(cfg, {}) }.to raise_error(Polyrun::Error, /workers/)
  end

  it "enforces source byte limits and allows the same source under a larger configured budget" do
    expect { Polyrun::Graph::Index.new(@root, settings: {"max_source_bytes" => 1}).call }.to raise_error(Polyrun::Graph::Error, /byte limit/)
    expect(Polyrun::Graph::Index.new(@root, settings: {"max_source_bytes" => 1000}).call["methods"].size).to eq(1)
  end

  it "excludes configured source files as well as directories" do
    File.write(File.join(@root, "lib/generated.rb"), "class Generated; def call; true; end; end")
    graph = Polyrun::Graph::Index.new(@root, settings: {"source_exclude" => ["lib/generated.rb"]}).call
    expect(graph["methods"].map { |method| method["subject"] }).to eq(["Account.value"])
  end

  it "uses a configured shared output ceiling for measurement commands" do
    path = File.join(@root, "polyrun.yml")
    settings = {"max_output_bytes" => 32, "quality" => {"measure" => {"enabled" => true,
                                                                      "command" => [Gem.ruby, "-e", "puts 'x' * 256"]}}}
    File.write(path, settings.to_yaml)
    output, status = polyrun("--config", path, "measure")
    expect(status.exitstatus).to eq(122), output
    expect(JSON.parse(output)["stdout"].bytesize).to eq(32)
  end

  it "configures staging budgets and hidden inputs while retaining key exclusions" do
    expect { Polyrun::Quality::Sandbox.new(@root, settings: {"max_bytes" => 1}) }.to raise_error(ArgumentError, /limit/)
    File.write(File.join(@root, ".inputs"), "input")
    File.write(File.join(@root, ".secret"), "hidden")
    File.write(File.join(@root, "private.key"), "fixture only")
    File.write(File.join(@root, "master.key"), "fixture only")
    Dir.mktmpdir do |destination|
      project = Polyrun::Quality::Sandbox.new(@root, settings: {"include_hidden" => [".inputs"]})
      project.copy_to(destination)
      expect(File).to exist(File.join(destination, ".inputs"))
      expect(File).not_to exist(File.join(destination, ".secret"))
      expect(File).not_to exist(File.join(destination, "private.key"))
      expect(File).not_to exist(File.join(destination, "master.key"))
    end
    Dir.mktmpdir do |destination|
      Polyrun::Quality::Sandbox.new(@root).copy_to(destination)
      expect(File).not_to exist(File.join(destination, ".inputs"))
      expect(File).not_to exist(File.join(destination, ".secret"))
    end
  end

  it "stages nested library coverage sources while excluding the project coverage report tree" do
    FileUtils.mkdir_p(File.join(@root, "lib/account/coverage"))
    FileUtils.mkdir_p(File.join(@root, "coverage"))
    File.write(File.join(@root, "lib/account/coverage/merge.rb"), "module Merge; end")
    File.write(File.join(@root, "coverage/index.html"), "report")
    Dir.mktmpdir do |destination|
      Polyrun::Quality::Sandbox.new(@root).copy_to(destination)
      expect(File).to exist(File.join(destination, "lib/account/coverage/merge.rb"))
      expect(File).not_to exist(File.join(destination, "coverage/index.html"))
    end
  end

  it "enforces configurable copy and worker limits before mutation execution" do
    command = [Gem.ruby, "-Ilib", "-raccount", "-e", "abort unless Account.value == 2"]
    runner = Polyrun::Mutation::Runner.new(root: @root, arguments: command, settings: {"max_copy_bytes" => 1})
    expect { runner.call(["Account.value"]) }.to raise_error(ArgumentError, /copy budget/)
    expect { Polyrun::Mutation::Runner.new(root: @root, workers: 2, settings: {"max_workers" => 1}) }.to raise_error(ArgumentError, /maximum/)
  end
end
