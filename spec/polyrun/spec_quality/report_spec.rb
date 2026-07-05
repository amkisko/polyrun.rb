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
          "profile" => {"wall" => 2.0, "gc_allocated" => 60_000, "cpu_user" => 0.6, "cpu_system" => 0.1},
          "sql_count" => 25,
          "factory_counts" => {"user" => 12}
        },
        "spec/slow_spec.rb:3" => {
          "unique_lines" => 1,
          "line_churn" => 10,
          "max_line_churn" => 10,
          "lines" => [["/lib/b.rb", 3, 10]],
          "profile" => {"wall" => 1.5, "gc_allocated" => 10_000},
          "polyrun_shard_index" => "1"
        }
      },
      "hot_lines" => {
        "/lib/a.rb:1" => {"examples" => ["spec/heavy_spec.rb:5"], "example_count" => 12, "total_hits" => 400},
        "/lib/b.rb:3" => {"examples" => ["spec/slow_spec.rb:3"], "example_count" => 2, "total_hits" => 20}
      },
      "shard_summary" => {
        "0" => {"examples" => 2, "zero_hit" => 1, "line_churn" => 1},
        "1" => {"examples" => 1, "zero_hit" => 0, "line_churn" => 1}
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

  it "analyze builds partition hints when plan shards are provided" do
    plan = {"0" => ["spec/heavy_spec.rb"], "1" => ["spec/slow_spec.rb"]}
    analysis = described_class.analyze(merged, {"hot_line_example_overlap" => 1}, plan_shards: plan)
    expect(analysis[:partition_hints]).not_to be_empty
    expect(analysis[:partition_hints].first[:shard]).to eq("0")
  end

  it "format_report includes partition hints and outlier profile dimensions" do
    plan = {"0" => ["spec/heavy_spec.rb"], "1" => ["spec/slow_spec.rb"]}
    text = described_class.format_report(
      merged,
      cfg: {"min_line_churn" => 5, "hot_line_example_overlap" => 1, "min_query_count" => 5},
      top: 5,
      profile: "wall,cpu,mem,io",
      plan_shards: plan
    )
    expect(text).to include("Partition hints")
    expect(text).to include("Correlated outliers")
    expect(text).to include("high_sql_count")
  end

  it "format_report shows empty sections when data is absent" do
    empty = {"examples" => {}, "hot_lines" => {}}
    text = described_class.format_report(empty, cfg: {})
    expect(text).to include("(none)")
    expect(text).to include("Shard attribution:")
  end

  it "gate_violations reports hot line overlap and minimum unique lines" do
    violations = described_class.gate_violations(
      merged,
      {"max_zero_hit_examples" => 0, "minimum_unique_lines_per_example" => 1, "max_hot_line_overlap" => 5}
    )
    expect(violations.join(" ")).to include("zero_hit_examples")
    expect(violations.join(" ")).to include("hot_line_overlap_count")
    expect(violations.join(" ")).to include("examples_below_minimum_unique_lines")
  end

  it "emit_warnings! logs churn rows" do
    expect(Polyrun::Log).to receive(:warn).with(include("spec/heavy_spec.rb:5"))
    described_class.emit_warnings!(merged, {"min_line_churn" => 50})
  end

  it "truncates long sections and formats io profile bits" do
    io_row = {
      "unique_lines" => 1,
      "line_churn" => 1,
      "max_line_churn" => 1,
      "profile" => {"wall" => 2.0, "io_read_bytes" => 10, "io_write_bytes" => 20},
      "lines" => []
    }
    many = (1..5).each_with_object({}) { |i, h| h["spec/x#{i}_spec.rb:1"] = io_row.dup }
    text = described_class.format_report(
      {"examples" => many, "hot_lines" => {}},
      cfg: {"min_line_churn" => 0},
      top: 2,
      profile: "io"
    )
    expect(text).to include("…")
    expect(text).to include("io=10/20")
  end

  it "format_report surfaces factory-heavy outliers" do
    row = {
      "unique_lines" => 1,
      "line_churn" => 1,
      "max_line_churn" => 1,
      "lines" => [],
      "profile" => {"wall" => 2.0},
      "factory_counts" => {"user" => 12}
    }
    text = described_class.format_report(
      {"examples" => {"spec/f_spec.rb:1" => row}, "hot_lines" => {}},
      cfg: {"min_query_count" => 99},
      top: 5
    )
    expect(text).to include("many_factories")
    expect(text).to include("slow_low_coverage")
  end

  it "format_outliers lists high allocation and cpu reasons" do
    row = {
      "unique_lines" => 1,
      "line_churn" => 1,
      "max_line_churn" => 1,
      "lines" => [],
      "profile" => {"wall" => 2.0, "gc_allocated" => 60_000, "cpu_user" => 0.4, "cpu_system" => 0.2}
    }
    text = described_class.format_report(
      {"examples" => {"spec/cpu_spec.rb:1" => row}, "hot_lines" => {}},
      cfg: {},
      top: 5
    )
    expect(text).to include("high_alloc")
    expect(text).to include("high_cpu_low_coverage")
  end

  it "format_outliers without profile lists score only" do
    row = {
      "unique_lines" => 0,
      "line_churn" => 0,
      "max_line_churn" => 0,
      "lines" => [],
      "profile" => {"wall" => 0.1}
    }
    text = described_class.format_report(
      {"examples" => {"spec/z_spec.rb:1" => row}, "hot_lines" => {}},
      cfg: {},
      top: 5,
      profile: nil
    )
    expect(text).to include("score=10")
    expect(text).not_to include("wall=")
  end
end
