require "spec_helper"
require "polyrun/spec_quality/report"

RSpec.describe Polyrun::SpecQuality::Report do
  let(:merged) do
    {
      "examples" => {
        "spec/empty_spec.rb:1" => {"unique_lines" => 0, "line_churn" => 0, "max_line_churn" => 0, "lines" => [], "profile" => {"wall" => 0.1}},
        "spec/heavy_spec.rb:5" => {
          "unique_lines" => 2,
          "line_churn" => 60,
          "max_line_churn" => 40,
          "lines" => [["/lib/a.rb", 1, 40], ["/lib/a.rb", 2, 20]],
          "profile" => {"wall" => 2.0, "gc_allocated" => 60_000},
          "sql_count" => 25
        }
      },
      "hot_lines" => {
        "/lib/a.rb:1" => {"examples" => ["spec/heavy_spec.rb:5"], "example_count" => 12, "total_hits" => 400}
      }
    }
  end

  it "formats zero-hit and churn sections" do
    text = described_class.format_report(merged, cfg: {"min_line_churn" => 50, "hot_line_example_overlap" => 10})
    expect(text).to include("Shard attribution")
    expect(text).to include("Zero production lines")
    expect(text).to include("spec/empty_spec.rb:1")
    expect(text).to include("spec/heavy_spec.rb:5")
    expect(text).to include("Hot lines")
  end

  it "reports gate violations" do
    violations = described_class.gate_violations(merged, {"max_zero_hit_examples" => 0})
    expect(violations).not_to be_empty
  end
end
