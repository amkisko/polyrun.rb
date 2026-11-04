require "spec_helper"
require "tmpdir"

RSpec.describe Polyrun::Config::Suite do
  describe ".merge" do
    it "deep-merges suite partition and workers onto the root config" do
      raw = {
        "workers" => 5,
        "partition" => {
          "shard_total" => 8,
          "strategy" => "round_robin",
          "paths_build" => {"all_glob" => "spec/**/*_spec.rb", "stages" => []}
        },
        "databases" => {"template_db" => "app_template"},
        "suites" => {
          "unit" => {
            "workers" => 2,
            "partition" => {
              "shard_total" => 2,
              "paths_build" => {"all_glob" => "spec/unit/**/*_spec.rb"}
            }
          }
        }
      }

      merged, name = described_class.merge(raw, "unit")
      expect(name).to eq("unit")
      expect(merged["workers"]).to eq(2)
      expect(merged["partition"]["shard_total"]).to eq(2)
      expect(merged["partition"]["strategy"]).to eq("round_robin")
      expect(merged["partition"]["paths_build"]["all_glob"]).to eq("spec/unit/**/*_spec.rb")
      expect(merged["partition"]["paths_build"]["stages"]).to eq([])
      expect(merged["databases"]["template_db"]).to eq("app_template")
      expect(merged["suites"]).to be_a(Hash)
    end

    it "returns the original raw when suite name is blank" do
      raw = {"partition" => {"shard_total" => 1}}
      merged, name = described_class.merge(raw, nil)
      expect(name).to be_nil
      expect(merged["partition"]["shard_total"]).to eq(1)
    end

    it "raises when the suite name is unknown" do
      raw = {"suites" => {"unit" => {"workers" => 1}}}
      expect { described_class.merge(raw, "missing") }.to raise_error(Polyrun::Error, /unknown suite/)
    end
  end
end
