require "spec_helper"
require "json"
require "tmpdir"

RSpec.describe Polyrun::Coverage::Reporting do
  it "writes selected formats from a coverage blob" do
    Dir.mktmpdir do |dir|
      blob = {"/a.rb" => {"lines" => [nil, 1, 0]}}
      paths = described_class.write(blob, output_dir: dir, basename: "out", formats: %w[json lcov console])
      expect(File).to exist(paths[:json])
      expect(File).to exist(paths[:lcov])
      expect(File).to exist(paths[:console])
      expect(File.read(paths[:console])).to include("Polyrun coverage summary")
    end
  end

  it "writes cobertura xml when requested" do
    Dir.mktmpdir do |dir|
      blob = {"/a.rb" => {"lines" => [1]}}
      paths = described_class.write(blob, output_dir: dir, basename: "c", formats: ["cobertura"])
      expect(File.read(paths[:cobertura])).to include("<coverage", "line-rate")
    end
  end

  it "write_from_json_file reads merged JSON" do
    Dir.mktmpdir do |dir|
      json = File.join(dir, "in.json")
      File.write(json, JSON.dump({"coverage" => {"/x.rb" => {"lines" => [1]}}}))
      out = File.join(dir, "out")
      paths = described_class.write_from_json_file(json, output_dir: out, basename: "r", formats: ["json"])
      expect(JSON.parse(File.read(paths[:json]))["coverage"]["/x.rb"]["lines"]).to eq([1])
    end
  end

  it "write_from_json_file passes meta and groups into JSON output" do
    Dir.mktmpdir do |dir|
      json = File.join(dir, "in.json")
      File.write(json, JSON.dump({
        "meta" => {"k" => "v"},
        "groups" => {"G" => {"lines" => {"covered_percent" => 50.0}}},
        "coverage" => {"/x.rb" => {"lines" => [1]}}
      }))
      out = File.join(dir, "out")
      paths = described_class.write_from_json_file(json, output_dir: out, basename: "g", formats: ["json"])
      j = JSON.parse(File.read(paths[:json]))
      expect(j["meta"]["k"]).to eq("v")
      expect(j["groups"]["G"]["lines"]["covered_percent"]).to eq(50.0)
    end
  end

  it "accepts a custom formatter" do
    Dir.mktmpdir do |dir|
      blob = {"/a.rb" => {"lines" => [1]}}
      fmt = Polyrun::Coverage::Formatter::HtmlFormatter.new(output_dir: dir, basename: "x")
      paths = described_class.write(blob, output_dir: dir, basename: "x", formatter: fmt)
      expect(paths[:html]).to end_with("x.html")
      expect(File.read(paths[:html])).to include("/a.rb")
    end
  end
end
