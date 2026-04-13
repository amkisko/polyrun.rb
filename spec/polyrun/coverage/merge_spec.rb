require "spec_helper"
require "json"

RSpec.describe Polyrun::Coverage::Merge do
  describe ".merge_two" do
    it "sums line hits for the same path" do
      a = {"/x.rb" => {"lines" => [nil, 1, 0, 2]}}
      b = {"/x.rb" => {"lines" => [nil, 0, 1, 1]}}
      m = described_class.merge_two(a, b)
      expect(m["/x.rb"]["lines"]).to eq([nil, 1, 1, 3])
    end

    it "preserves ignored markers" do
      a = {"/x.rb" => {"lines" => [1, "ignored"]}}
      b = {"/x.rb" => {"lines" => [2, 0]}}
      m = described_class.merge_two(a, b)
      expect(m["/x.rb"]["lines"]).to eq([3, "ignored"])
    end

    it "sums integer and numeric string line hits" do
      a = {"/x.rb" => {"lines" => [1, "2"]}}
      b = {"/x.rb" => {"lines" => [0, 3]}}
      m = described_class.merge_two(a, b)
      expect(m["/x.rb"]["lines"]).to eq([1, 5])
    end

    it "accepts SimpleCov pre-0.18 raw line arrays per file" do
      legacy = {"/x.rb" => [nil, 1, 0]}
      modern = {"/x.rb" => {"lines" => [nil, 0, 2]}}
      m = described_class.merge_two(legacy, modern)
      expect(m["/x.rb"]["lines"]).to eq([nil, 1, 2])
    end

    it "merges branch coverage by key" do
      a = {
        "/x.rb" => {
          "lines" => [1],
          "branches" => [
            {"type" => "then", "start_line" => 1, "end_line" => 1, "coverage" => 1}
          ]
        }
      }
      b = {
        "/x.rb" => {
          "lines" => [1],
          "branches" => [
            {"type" => "then", "start_line" => 1, "end_line" => 1, "coverage" => 2}
          ]
        }
      }
      m = described_class.merge_two(a, b)
      expect(m["/x.rb"]["branches"].first["coverage"]).to eq(3)
    end

    it "orders merged branches deterministically by branch_key" do
      br_then = {"type" => "then", "start_line" => 1, "end_line" => 1, "coverage" => 1}
      br_else = {"type" => "else", "start_line" => 2, "end_line" => 2, "coverage" => 1}
      a = {"/x.rb" => {"lines" => [1], "branches" => [br_then, br_else]}}
      b = {"/x.rb" => {"lines" => [1], "branches" => [br_else, br_then]}}
      m1 = described_class.merge_two(a, b)
      m2 = described_class.merge_two(b, a)
      expect(m1["/x.rb"]["branches"]).to eq(m2["/x.rb"]["branches"])
      expect(m1["/x.rb"]["branches"].map { |br| br["type"] }).to eq(%w[else then])
    end
  end

  describe ".extract_coverage_blob" do
    it "reads top-level export format" do
      j = {"coverage" => {"/a.rb" => {"lines" => [1]}}}
      expect(described_class.extract_coverage_blob(j)).to eq(j["coverage"])
    end

    it "reads SimpleCov resultset style" do
      j = {"RSpec" => {"coverage" => {"/a.rb" => {"lines" => [1]}}, "timestamp" => 1}}
      expect(described_class.extract_coverage_blob(j)).to eq({"/a.rb" => {"lines" => [1]}})
    end

    it "merges multiple suite coverages" do
      j = {
        "RSpec" => {"coverage" => {"/a.rb" => {"lines" => [1, 0]}}},
        "Minitest" => {"coverage" => {"/a.rb" => {"lines" => [0, 2]}}}
      }
      expect(described_class.extract_coverage_blob(j)["/a.rb"]["lines"]).to eq([1, 2])
    end

    it "merges legacy raw arrays from suite coverages" do
      j = {
        "RSpec" => {"coverage" => {"/a.rb" => [1, 0]}},
        "Minitest" => {"coverage" => {"/a.rb" => {"lines" => [0, 2]}}}
      }
      expect(described_class.extract_coverage_blob(j)["/a.rb"]["lines"]).to eq([1, 2])
    end

    it "merges top-level coverage with suite entries" do
      j = {
        "coverage" => {"/a.rb" => {"lines" => [1, 0]}},
        "RSpec" => {"coverage" => {"/a.rb" => {"lines" => [0, 2]}}}
      }
      expect(described_class.extract_coverage_blob(j)["/a.rb"]["lines"]).to eq([1, 2])
    end
  end
end
