require "spec_helper"

RSpec.describe Polyrun::Benchmark::Report do
  let(:profile_data) do
    {
      "meta" => {
        "commit" => "abc123",
        "recorded_at" => "2026-07-13T12:00:00Z",
        "ruby" => RUBY_VERSION
      },
      "lines" => ["Coverage merge:", "  merge_two: 0.07s"],
      "metrics" => [
        {"section" => "Coverage merge", "name" => "merge_two", "value" => 0.07, "unit" => "seconds"}
      ]
    }
  end

  it "renders CSV from structured metrics" do
    csv = described_class.render(profile_data, format: "csv")
    expect(csv).to include("section,name,value,unit")
    expect(csv).to include("merge_two")
  end

  it "renders Markdown with metadata and metrics" do
    markdown = described_class.render(profile_data, format: "markdown")
    expect(markdown).to include("# Polyrun benchmark profile")
    expect(markdown).to include("merge_two")
  end
end
