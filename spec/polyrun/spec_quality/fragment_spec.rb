require "spec_helper"
require "polyrun/spec_quality/fragment"

RSpec.describe Polyrun::SpecQuality::Fragment do
  it "default_fragment_path uses shard basename from env" do
    env = {"POLYRUN_SHARD_INDEX" => "2", "POLYRUN_SHARD_TOTAL" => "4"}
    path = described_class.default_fragment_path(env)
    expect(path).to end_with("polyrun-spec-quality-fragment-worker2.jsonl")
  end

  it "glob_pattern matches coverage fragments" do
    expect(described_class.glob_pattern("/tmp")).to include("polyrun-spec-quality-fragment-")
  end

  it "append_row! writes JSONL rows" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "coverage", "frag.jsonl")
      described_class.append_row!(path, {"example" => "spec/a_spec.rb:1"})
      expect(File.read(path).strip).to include("spec/a_spec.rb:1")
    end
  end

  it "truncate_fragment! creates an empty file" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "coverage", "frag.jsonl")
      described_class.append_row!(path, {"example" => "x"})
      described_class.truncate_fragment!(path)
      expect(File.read(path)).to eq("")
    end
  end
end
