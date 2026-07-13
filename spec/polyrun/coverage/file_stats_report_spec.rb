require "spec_helper"

RSpec.describe Polyrun::Coverage::FileStatsReport do
  let(:blob) do
    {
      "/a.rb" => {"lines" => [nil, 1, 0]},
      "/b.rb" => {"lines" => [1, 1]}
    }
  end

  it "emits per-file CSV rows sorted by lowest line percent" do
    csv = described_class.emit_csv(blob)
    expect(csv).to include("path,line_percent,lines_covered,lines_relevant")
    expect(csv.lines.map(&:strip)).to include("/a.rb,50.00,1,2")
    expect(csv.lines.map(&:strip)).to include("/b.rb,100.00,2,2")
  end

  it "emits markdown with summary and table" do
    markdown = described_class.emit_markdown(blob)
    expect(markdown).to include("# Polyrun coverage report")
    expect(markdown).to include("Polyrun coverage summary")
    expect(markdown).to include("| path | line_percent |")
    expect(markdown).to include("/a.rb")
  end
end
