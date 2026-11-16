require "spec_helper"

RSpec.describe Polyrun::Coverage::Merge do
  before { skip "native extension not loaded" unless described_class.native_acceleration? }

  it "preserves exact sums across the immediate integer boundary" do
    boundary = 2**(0.size * 8 - 2)
    values = [0, 1, boundary - 1, boundary, boundary + 1, 10**100]
    values += values.map { |value| -value }
    values.uniq.repeated_permutation(2) do |left, right|
      expect(described_class.merge_line_arrays([left], [right])).to eq([left + right]),
        "sum of #{left} and #{right}"
    end
  end

  it "uses Ruby integer conversion for string and numeric counts" do
    values = ["0", "1_000", " 12 ", "0x10", "010", (10**100).to_s,
      (-10**100).to_s, "invalid", "1x", "", 2.5, Float::INFINITY, :invalid]
    values.each do |value|
      converted = Integer(value, exception: false)
      expect(described_class.merge_line_arrays([value], [1])).to eq([(converted || 0) + 1]), value.inspect
      expect(described_class.line_counts({"lines" => [value]})).to eq(
        relevant: 1, covered: (converted && converted.positive?) ? 1 : 0
      ), value.inspect
    end
  end

  it "preserves exact branch totals after integer conversion" do
    boundary = 2**(0.size * 8 - 2)
    branch = {"type" => "then", "start_line" => 1, "end_line" => 1, "coverage" => (10**100).to_s}
    left = {"lib/sample.rb" => {"lines" => [], "branches" => [branch]}}
    right = {"lib/sample.rb" => {"lines" => [], "branches" => [branch.merge("coverage" => boundary)]}}
    expect(described_class.merge_two(left, right)["lib/sample.rb"]["branches"].first["coverage"]).to eq(10**100 + boundary)
  end

  it "reads subsequent counts after a conversion replaces the input array" do
    left = []
    count = Object.new
    count.define_singleton_method(:to_int) do
      left.replace([2, 3, 4, 5, 6])
      2
    end
    left.replace([count, 50, 60, 70])
    expect(described_class.merge_line_arrays(left, [1, 1, 1, 1])).to eq([3, 4, 5, 6])
  end
end
