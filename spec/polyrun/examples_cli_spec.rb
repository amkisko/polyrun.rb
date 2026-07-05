require "spec_helper"

RSpec.describe "examples CLI surface" do
  it "help documents ci-shard and config commands" do
    out, status = polyrun("help")
    expect(status.success?).to be true
    expect(out).to include("ci-shard-run")
    expect(out).to include("ci-shard-rspec")
    expect(out).to include("config")
    expect(out).to include("run-shards")
    expect(out).not_to include("install_")
    expect(out).not_to include("Polyrun::")
  end
end
