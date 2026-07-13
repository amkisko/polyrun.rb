require "spec_helper"

RSpec.describe Polyrun::Export::Markdown do
  it "renders a markdown table" do
    table = described_class.table(%w[rank path], [[1, "/a.rb"]])
    expect(table).to include("| rank | path |")
    expect(table).to include("| 1 | /a.rb |")
  end

  it "renders a document with sections" do
    document = described_class.document(
      "Report",
      [
        {heading: "Summary", body: "All good"},
        {heading: "Rows", headers: %w[path], rows: [["/a.rb"]]}
      ]
    )
    expect(document).to include("# Report")
    expect(document).to include("## Summary")
    expect(document).to include("All good")
    expect(document).to include("| path |")
  end
end
