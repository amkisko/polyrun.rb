require "spec_helper"

RSpec.describe Polyrun::Timing::Stats do
  describe ".merge_entries" do
    it "defaults mean to 0.0 when both sides have zero runs" do
      merged = described_class.merge_entries({"runs" => 0, "mean" => 5.0}, {"runs" => 0, "mean" => 3.0})
      expect(merged["runs"]).to eq(0)
      expect(merged["mean"]).to eq(0.0)
      expect(merged["mean"]).not_to be_nan
    end
  end
end
