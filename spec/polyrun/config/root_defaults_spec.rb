require "spec_helper"
require "polyrun/spec_quality/config"

RSpec.describe "root shared defaults" do
  it "validates root defaults without activating any feature" do
    Dir.mktmpdir do |root|
      path = File.join(root, "polyrun.yml")
      File.write(path, {"workers" => 2, "timeout" => 7, "command" => [Gem.ruby, "-e", "exit 0"], "max_output_bytes" => 32}.to_yaml)
      output, status = polyrun("--config", path, "validate")
      expect(status.exitstatus).to eq(0), output
      output, status = polyrun("--config", path, "config", "quality.measure")
      expect(status.exitstatus).to eq(0), output
      expect(JSON.parse(output)).to include("enabled" => false, "timeout" => 7, "max_output_bytes" => 32)
      output, status = polyrun("--config", path, "config", "mutation")
      expect(status.exitstatus).to eq(0), output
      expect(JSON.parse(output)).to include("enabled" => false, "workers" => 2)
    end
  end

  it "merges root defaults through suite and feature settings before environment and CLI overrides" do
    raw = {"timeout" => 30, "command" => ["original"], "staging" => {"max_bytes" => 1024, "max_files" => 10},
           "suites" => {"review" => {"timeout" => 5, "command" => ["review"], "staging" => {"max_files" => 2}, "graph" => {"timeout" => 1}}}}
    merged, = Polyrun::Config::Suite.merge(raw, "review")
    cfg = Polyrun::Config.new(path: nil, raw: merged)
    graph = Polyrun::Config::Tools.resolve(cfg, "graph", env: {})
    expect(graph).to include("timeout" => 1, "command" => ["review"])
    expect(graph["staging"]).to include("max_bytes" => 1024, "max_files" => 2)
    measure = Polyrun::Config::Tools.resolve(cfg, "measure", env: {})
    expect(measure["timeout"]).to eq(5)
    graph = Polyrun::Config::Tools.resolve(cfg, "graph", env: {"POLYRUN_TIMEOUT" => "9"}, overrides: {timeout: 11})
    expect(graph["timeout"]).to eq(11)
  end

  it "shares the root source scope with per-example quality collection" do
    Dir.mktmpdir do |root|
      File.write(File.join(root, "polyrun.yml"), {"source_roots" => ["src"]}.to_yaml)
      expect(Polyrun::SpecQuality::Config.load(root: root, env: {})["track_under"]).to eq(["src"])
    end
  end

  it "rejects the removed global section before graph state is created" do
    Dir.mktmpdir do |root|
      path = File.join(root, "polyrun.yml")
      File.write(path, {"global" => {"timeout" => 5}, "graph" => {"enabled" => true, "root" => root}}.to_yaml)
      output, status = polyrun("--config", path, "validate")
      expect(status.exitstatus).to eq(1), output
      expect(output).to include("global")
      output, status = polyrun("--config", path, "graph", "index", "--json")
      expect(status.exitstatus).to eq(2), output
      expect(JSON.parse(output)["message"]).to include("global")
      expect(File.exist?(File.join(root, ".polyrun"))).to be(false)
    end
  end

  it "rejects the removed global section inside a selected suite" do
    raw = {"suites" => {"review" => {"global" => {"workers" => 2}}}}
    expect { Polyrun::Config::Suite.merge(raw, "review") }.to raise_error(Polyrun::Error, /global/)
  end
end
