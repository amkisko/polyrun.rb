require "spec_helper"
require "polyrun/spec_quality/plan_loader"
require "polyrun/spec_quality/merge"

RSpec.describe Polyrun::SpecQuality do
  describe Polyrun::SpecQuality::PlanLoader do
    it "loads polyrun plan manifest per shard" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "plan-0.json")
        File.write(path, JSON.generate("shard_index" => 0, "paths" => ["/app/spec/a_spec.rb"]))
        shards = described_class.load_shards([path])
        expect(shards["0"]).to eq(["/app/spec/a_spec.rb"])
      end
    end

    it "resolves shard for example locator" do
      plan = {"0" => ["/app/spec/foo_spec.rb"], "1" => ["/app/spec/bar_spec.rb"]}
      expect(described_class.shard_for_example("/app/spec/foo_spec.rb:12", plan)).to eq("0")
      expect(described_class.shard_for_example("/app/spec/bar_spec.rb:3", plan)).to eq("1")
    end
  end

  describe Polyrun::SpecQuality::Merge do
    it "builds shard_summary" do
      examples = {
        "spec/a_spec.rb:1" => {"unique_lines" => 0, "line_churn" => 0, "polyrun_shard_index" => "0"},
        "spec/b_spec.rb:2" => {"unique_lines" => 2, "line_churn" => 5, "polyrun_shard_index" => "1"}
      }
      summary = described_class.shard_summary(examples)
      expect(summary["0"]["zero_hit"]).to eq(1)
      expect(summary["1"]["line_churn"]).to eq(5)
    end
  end
end
