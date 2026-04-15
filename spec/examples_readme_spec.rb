require "spec_helper"

RSpec.describe "examples/README.md" do
  let(:readme) do
    path = File.expand_path("../examples/README.md", __dir__)
    File.read(path, encoding: Encoding::UTF_8)
  end

  it "documents effective config / polyrun config" do
    expect(readme).to include("polyrun config")
    expect(readme).to match(/[Ee]ffective|Polyrun::Config::Effective/)
  end

  it "documents default polyrun and matrix ci-shard commands" do
    expect(readme).to match(/no subcommand|path-only|default parallel suite/)
    expect(readme).to include("ci-shard")
  end

  it "documents binstubs or bin/polyrun" do
    expect(readme).to match(/binstubs|bin\/polyrun/)
  end
end
