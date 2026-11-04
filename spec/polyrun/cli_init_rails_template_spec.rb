require "spec_helper"
require "tmpdir"
require "yaml"

RSpec.describe "polyrun init rails profile", :aggregate_failures do
  it "writes start gates, hooks stubs, and merge_failures commentary" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        out, status = polyrun("init", "--profile", "rails")
        expect(status.success?).to be true
        expect(out).to include("wrote")
        raw = File.read("polyrun.yml")
        data = YAML.safe_load(raw, permitted_classes: [Symbol], aliases: true)
        expect(data["version"]).to eq(1)
        expect(data.dig("start", "prepare")).to eq(true)
        expect(data.dig("start", "databases")).to eq(true)
        expect(data["hooks"]).to be_a(Hash)
        expect(raw).to include("merge_failures")
        expect(raw).to include("connections")
      end
    end
  end
end
