require "spec_helper"

RSpec.describe Polyrun::Export::Csv do
  it "escapes commas, quotes, and newlines" do
    expect(described_class.escape_field("plain")).to eq("plain")
    expect(described_class.escape_field("a,b")).to eq('"a,b"')
    expect(described_class.escape_field(%(say "hi"))).to eq(%("say ""hi"""))
    expect(described_class.escape_field("line\nbreak")).to eq("\"line\nbreak\"")
  end

  it "generates a header row and data rows" do
    csv = described_class.generate(%w[rank path], [[1, "/a.rb"], [2, "/b.rb"]])
    expect(csv).to eq("rank,path\n1,/a.rb\n2,/b.rb\n")
  end
end
