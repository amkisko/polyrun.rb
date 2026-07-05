require "spec_helper"
require "polyrun/spec_quality/report"

RSpec.describe Polyrun::SpecQuality::Report do
  it "analyze derives shard_summary when merged JSON omits it" do
    merged = {
      "examples" => {
        "spec/a_spec.rb:1" => {"unique_lines" => 1, "line_churn" => 2, "lines" => []},
        "spec/b_spec.rb:1" => {"unique_lines" => 0, "line_churn" => 0, "lines" => []}
      },
      "hot_lines" => {}
    }
    analysis = described_class.analyze(merged, {"min_line_churn" => 99})
    expect(analysis[:shard_summary]).not_to be_empty
    expect(analysis[:line_churn]).to be_empty
    expect(analysis[:partition_hints]).to be_nil
  end

  it "format_report prints wall and mem profile dimensions" do
    row = {
      "unique_lines" => 1,
      "line_churn" => 1,
      "max_line_churn" => 1,
      "lines" => [],
      "profile" => {"wall" => 1.5, "gc_allocated" => 12_000, "cpu_user" => 0.1, "cpu_system" => 0.1}
    }
    text = described_class.format_report(
      {"examples" => {"spec/w_spec.rb:1" => row}, "hot_lines" => {}},
      cfg: {},
      top: 5,
      profile: "wall,mem"
    )
    expect(text).to include("wall=1.50")
    expect(text).to include("alloc=12000")
  end

  it "gate_violations returns empty when thresholds are satisfied" do
    merged = {
      "examples" => {
        "spec/ok_spec.rb:1" => {"unique_lines" => 5, "line_churn" => 1, "lines" => []}
      },
      "hot_lines" => {"/lib/x.rb:1" => {"examples" => ["spec/ok_spec.rb:1"], "example_count" => 1, "total_hits" => 1}}
    }
    violations = described_class.gate_violations(
      merged,
      {"max_zero_hit_examples" => 1, "minimum_unique_lines_per_example" => 1, "max_hot_line_overlap" => 5}
    )
    expect(violations).to be_empty
  end

  it "partition hints use polyrun_shard_index when plan shards omit an example" do
    merged = {
      "examples" => {
        "spec/slow_spec.rb:3" => {
          "unique_lines" => 1,
          "line_churn" => 1,
          "lines" => [],
          "polyrun_shard_index" => "2"
        }
      },
      "hot_lines" => {
        "/lib/b.rb:3" => {"examples" => ["spec/slow_spec.rb:3"], "example_count" => 2, "total_hits" => 20}
      }
    }
    plan = {"0" => ["spec/other_spec.rb"]}
    text = described_class.format_report(
      merged,
      cfg: {"hot_line_example_overlap" => 1},
      top: 5,
      plan_shards: plan
    )
    expect(text).to include("Partition hints")
    expect(text).to include("shard 2")
  end

  it "format_report truncates zero-hit section when many examples have no hits" do
    row = {"unique_lines" => 0, "line_churn" => 0, "max_line_churn" => 0, "lines" => []}
    examples = (1..4).each_with_object({}) { |i, h| h["spec/x#{i}_spec.rb:1"] = row.dup }
    text = described_class.format_report(
      {"examples" => examples, "hot_lines" => {}},
      cfg: {},
      top: 2
    )
    expect(text).to include("…")
  end
end
