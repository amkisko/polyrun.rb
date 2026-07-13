require "spec_helper"

RSpec.describe Polyrun::Coverage::Merge do
  def native_acceleration_available?
    described_class.native_acceleration?
  end

  def expect_native_parity(native_result, ruby_result = nil)
    skip "native extension not loaded" unless native_acceleration_available?

    expect(native_result).to eq(ruby_result) if ruby_result
    yield if block_given? && ruby_result.nil?
  end

  describe ".merge_line_arrays" do
    it "matches the Ruby fallback for mixed line hits" do
      left = [nil, 1, 0, 2, "ignored", "3"]
      right = [0, 0, 1, 1, 0, 1]
      expect_native_parity(
        described_class.merge_line_arrays(left, right),
        described_class.merge_line_arrays_ruby(left, right)
      )
    end

    context "when native acceleration is available" do
      before { skip "native extension not loaded" unless native_acceleration_available? }

      it "matches the Ruby fallback for nil and empty operands" do
        expect(described_class.merge_line_arrays(nil, nil)).to eq(
          described_class.merge_line_arrays_ruby(nil, nil)
        )
        expect(described_class.merge_line_arrays([], [1])).to eq(
          described_class.merge_line_arrays_ruby([], [1])
        )
      end

      it "matches the Ruby fallback for bignum line hits" do
        big = 10**100
        left = [big, 1]
        right = [big, 1]
        expect(described_class.merge_line_arrays(left, right)).to eq(
          described_class.merge_line_arrays_ruby(left, right)
        )
      end

      it "matches the Ruby fallback on a long line array" do
        size = 5_000
        left = Array.new(size) { |index| index.even? ? 1 : 0 }
        right = Array.new(size) { |index| index.odd? ? 2 : 0 }
        expect(described_class.merge_line_arrays(left, right)).to eq(
          described_class.merge_line_arrays_ruby(left, right)
        )
      end

      it "raises when operands are not line arrays" do
        expect { described_class.merge_line_arrays(1, []) }.to raise_error(TypeError, /Array/)
        expect { described_class.merge_line_arrays([], {}) }.to raise_error(TypeError, /Array/)
      end
    end
  end

  describe ".line_counts" do
    it "matches the Ruby fallback for mixed line hits" do
      entry = {"lines" => [nil, 1, 0, "ignored", 2, "3"]}
      expect_native_parity(
        described_class.line_counts(entry),
        described_class.line_counts_ruby(entry)
      )
    end

    it "matches the Ruby fallback for legacy raw arrays" do
      entry = [nil, 0, 4]
      expect_native_parity(
        described_class.line_counts(entry),
        described_class.line_counts_ruby(entry)
      )
    end

    context "when native acceleration is available" do
      before { skip "native extension not loaded" unless native_acceleration_available? }

      it "matches the Ruby fallback for nil, empty, and invalid entries" do
        expect(described_class.line_counts(nil)).to eq(described_class.line_counts_ruby(nil))
        expect(described_class.line_counts({})).to eq(described_class.line_counts_ruby({}))
        expect(described_class.line_counts({"lines" => "bad"})).to eq(
          described_class.line_counts_ruby({"lines" => "bad"})
        )
        expect(described_class.line_counts(true)).to eq(described_class.line_counts_ruby(true))
      end

      it "matches the Ruby fallback for symbol line keys and bignum hits" do
        entry = {lines: [10**50, 0, nil, "ignored"]}
        expect(described_class.line_counts(entry)).to eq(described_class.line_counts_ruby(entry))
      end
    end
  end

  describe "native acceleration" do
    it "reports whether the optional extension is loaded" do
      actual = described_class.native_acceleration?
      expect(actual).to be(true).or be(false)
    end

    it "keeps merge_two identical with the Ruby fallback" do
      random = Random.new(11)
      left = {}
      right = {}
      12.times do |index|
        path = "/project/file_#{index}.rb"
        left[path] = {"lines" => Array.new(40) { random.rand(0..5) }}
        right[path] = {"lines" => Array.new(40) { random.rand(0..5) }}
      end
      expect_native_parity(
        described_class.merge_two(left, right),
        described_class.merge_two_ruby(left, right)
      )
    end

    it "keeps branch merges identical with the Ruby fallback" do
      branch = {"type" => "then", "start_line" => 1, "end_line" => 1, "coverage" => 1}
      left = {"/x.rb" => {"lines" => [1], "branches" => [branch]}}
      right = {"/x.rb" => {"lines" => [2], "branches" => [branch.merge("coverage" => 2)]}}
      expect_native_parity(
        described_class.merge_two(left, right),
        described_class.merge_two_ruby(left, right)
      )
    end

    it "matches the Ruby fallback on random line-only blobs", :aggregate_failures do
      skip "native extension not loaded" unless native_acceleration_available?

      random = Random.new(99)
      25.times do
        left = {}
        right = {}
        random.rand(3..8).times do |index|
          path = "/project/model_#{index}.rb"
          left[path] = {"lines" => Array.new(random.rand(20..80)) { random.rand(0..5) }}
          right[path] = {"lines" => Array.new(random.rand(20..80)) { random.rand(0..5) }}
        end
        expect(described_class.merge_two(left, right)).to eq(described_class.merge_two_ruby(left, right))
      end
    end

    context "when native acceleration is available" do
      before { skip "native extension not loaded" unless native_acceleration_available? }

      it "matches the Ruby fallback for nil and empty operands" do
        expect(described_class.merge_two(nil, nil)).to eq(described_class.merge_two_ruby(nil, nil))
        expect(described_class.merge_two({}, {})).to eq(described_class.merge_two_ruby({}, {}))
      end

      it "matches the Ruby fallback for disjoint file keys and missing entries" do
        left = {"/only_left.rb" => {"lines" => [1]}}
        right = {"/only_right.rb" => {"lines" => [2]}}
        expect(described_class.merge_two(left, right)).to eq(described_class.merge_two_ruby(left, right))
      end

      it "matches the Ruby fallback for symbol keys and sparse branch metadata" do
        branch = {type: "then", start_line: 1, end_line: 1, coverage: 1}
        sparse_branch = {type: "else", start_line: 2, end_line: 2}
        left = {"/x.rb" => {lines: [1], branches: [branch, sparse_branch]}}
        right = {"/x.rb" => {lines: [2], branches: [branch.merge(coverage: 2), sparse_branch]}}
        expect(described_class.merge_two(left, right)).to eq(described_class.merge_two_ruby(left, right))
      end

      it "matches the Ruby fallback when branch lists include non-hash entries" do
        branch = {"type" => "then", "start_line" => 1, "end_line" => 1, "coverage" => 1}
        left = {"/x.rb" => {"lines" => [1], "branches" => [branch, "skip-me", nil]}}
        right = {"/x.rb" => {"lines" => [2], "branches" => [branch.merge("coverage" => 2)]}}
        expect(described_class.merge_two(left, right)).to eq(described_class.merge_two_ruby(left, right))
      end

      it "requires hash operands from the native entry point" do
        expect { Polyrun::Coverage::MergeNative.merge_two("", {}) }.to raise_error(TypeError, /Hash/)
        expect { Polyrun::Coverage::MergeNative.merge_two({}, 1) }.to raise_error(TypeError, /Hash/)
      end

      it "rejects non-array branches when both sides define branches" do
        left = {"/x.rb" => {"lines" => [1], "branches" => 1}}
        right = {"/x.rb" => {"lines" => [1], "branches" => []}}
        expect { described_class.merge_two(left, right) }.to raise_error(TypeError, /Array/)
      end
    end
  end
end
