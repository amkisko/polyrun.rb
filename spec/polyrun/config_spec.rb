require "spec_helper"
require "tmpdir"

RSpec.describe Polyrun::Config do
  it "raises when an explicit config path is missing" do
    expect do
      described_class.load(path: "/nonexistent/polyrun.yml")
    end.to raise_error(Polyrun::Error, /config not found/)
  end

  it "loads empty hash when no path is given and no default file exists" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        c = described_class.load
        expect(c.raw).to eq({})
        expect(c.path).to be_nil
      end
    end
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
