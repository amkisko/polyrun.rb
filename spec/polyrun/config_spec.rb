require "spec_helper"
require "tmpdir"

RSpec.describe Polyrun::Config do
  it "loads empty hash when file missing" do
    c = described_class.load(path: "/nonexistent/polyrun.yml")
    expect(c.raw).to eq({})
  end

  it "loads YAML from path" do
    Dir.mktmpdir do |dir|
      p = File.join(dir, "polyrun.yml")
      File.write(p, <<~YAML)
        partition:
          strategy: round_robin
        prepare:
          recipe: default
      YAML
      c = described_class.load(path: p)
      expect(c.partition["strategy"]).to eq("round_robin")
      expect(c.prepare["recipe"]).to eq("default")
    end
  end
end
