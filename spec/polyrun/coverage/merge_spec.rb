require "spec_helper"
require "json"
require "tmpdir"
require "fileutils"

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

  describe ".emit_cobertura" do
    it "emits class and line elements with geninfo-style root metrics" do
      xml = described_class.emit_cobertura({"/app/x.rb" => {"lines" => [nil, 3]}})
      expect(xml).to include("<!DOCTYPE coverage SYSTEM")
      expect(xml).to include('lines-valid="1"')
      expect(xml).to include('lines-covered="1"')
      expect(xml).to match(/line-rate="1(\.0+)?"/)
      expect(xml).to match(/timestamp="\d+"/)
      expect(xml).to include('filename="/app/x.rb"')
      expect(xml).to include('number="2" hits="3"')
    end

    it "emits filename relative to root when root is set" do
      root = "/project"
      abs = File.join(root, "lib", "foo.rb")
      xml = described_class.emit_cobertura({abs => {"lines" => [nil, 1]}}, root: root)
      expect(xml).to include('filename="lib/foo.rb"')
    end
  end

  describe ".merge_files" do
    it "merges two files from disk" do
      Dir.mktmpdir do |dir|
        a = File.join(dir, "a.json")
        b = File.join(dir, "b.json")
        File.write(a, JSON.dump({"coverage" => {"/x.rb" => {"lines" => [nil, 1]}}}))
        File.write(b, JSON.dump({"coverage" => {"/x.rb" => {"lines" => [nil, 2]}}}))
        m = described_class.merge_files([a, b])
        expect(m["/x.rb"]["lines"]).to eq([nil, 3])
      end
    end
  end

  describe ".merge_fragments" do
    it "recomputes groups from merged blob using meta from fragments" do
      Dir.mktmpdir do |root|
        lib_a = File.join(root, "lib", "a.rb")
        lib_b = File.join(root, "lib", "b.rb")
        f1 = File.join(root, "s0.json")
        f2 = File.join(root, "s1.json")
        meta = {
          "polyrun_coverage_root" => root,
          "polyrun_coverage_groups" => {
            "Lib" => "lib/**/*.rb"
          }
        }
        File.write(f1, JSON.dump({"meta" => meta, "coverage" => {lib_a => {"lines" => [nil, 1, 0]}}}))
        File.write(f2, JSON.dump({"meta" => meta, "coverage" => {lib_b => {"lines" => [nil, 1]}}}))
        r = described_class.merge_fragments([f1, f2])
        expect(r[:blob][lib_a]["lines"]).to eq([nil, 1, 0])
        expect(r[:blob][lib_b]["lines"]).to eq([nil, 1])
        expect(r[:groups]["Lib"]["lines"]["covered_percent"]).to eq(66.67)
      end
    end

    it "matches left-associative merge_files on blob" do
      blobs = [
        {"/a.rb" => {"lines" => [1]}},
        {"/a.rb" => {"lines" => [2]}},
        {"/b.rb" => {"lines" => [3]}}
      ]
      left = blobs.reduce { |acc, el| described_class.merge_two(acc, el) }
      tree = described_class.merge_blob_tree(blobs)
      expect(tree).to eq(left)
    end

    it "applies polyrun_track_files once after merge (matches single-pass untracked expansion)" do
      Dir.mktmpdir do |root|
        FileUtils.mkdir_p(File.join(root, "lib"))
        File.write(File.join(root, "lib", "a.rb"), "x = 1\n")
        File.write(File.join(root, "lib", "b.rb"), "y = 2\n")
        File.write(File.join(root, "lib", "c.rb"), "z = 3\n")
        lib_a = File.join(root, "lib", "a.rb")
        lib_b = File.join(root, "lib", "b.rb")
        lib_c = File.join(root, "lib", "c.rb")
        f1 = File.join(root, "s0.json")
        f2 = File.join(root, "s1.json")
        meta = {
          "polyrun_coverage_root" => root,
          "polyrun_track_files" => "lib/**/*.rb"
        }
        File.write(f1, JSON.dump({"meta" => meta, "coverage" => {lib_a => {"lines" => [nil, 1]}}}))
        File.write(f2, JSON.dump({"meta" => meta, "coverage" => {lib_b => {"lines" => [nil, 1]}}}))
        r = described_class.merge_fragments([f1, f2])
        merged_partial = described_class.merge_two(
          {lib_a => {"lines" => [nil, 1]}},
          {lib_b => {"lines" => [nil, 1]}}
        )
        expected = Polyrun::Coverage::TrackFiles.merge_untracked_into_blob(merged_partial, root, "lib/**/*.rb")
        expect(r[:blob].keys.sort).to eq(expected.keys.sort)
        expect(r[:blob][lib_c]["lines"]).to eq(expected[lib_c]["lines"])
        s = described_class.console_summary(r[:blob])
        e = described_class.console_summary(expected)
        expect(s[:lines_relevant]).to eq(e[:lines_relevant])
        expect(s[:lines_covered]).to eq(e[:lines_covered])
      end
    end
  end

  describe ".to_simplecov_json" do
    it "wraps coverage with meta" do
      out = described_class.to_simplecov_json({"/a.rb" => {"lines" => [1]}}, meta: {"simplecov_version" => "0.22"})
      expect(out["meta"]["simplecov_version"]).to eq("0.22")
      expect(out["coverage"]["/a.rb"]["lines"]).to eq([1])
      expect(out["groups"]).to eq({})
    end

    it "embeds group stats when provided" do
      g = {"Models" => {"lines" => {"covered_percent" => 88.5}}}
      out = described_class.to_simplecov_json({"/a.rb" => {"lines" => [1]}}, groups: g)
      expect(out["groups"]["Models"]["lines"]["covered_percent"]).to eq(88.5)
    end

    it "strips internal polyrun meta keys from output by default" do
      out = described_class.to_simplecov_json(
        {"/a.rb" => {"lines" => [1]}},
        meta: {
          "polyrun_coverage_root" => "/app",
          "polyrun_coverage_groups" => {"G" => "lib/**/*.rb"},
          "polyrun_track_files" => "lib/**/*.rb"
        },
        groups: {}
      )
      expect(out["meta"]).not_to have_key("polyrun_coverage_root")
      expect(out["meta"]).not_to have_key("polyrun_coverage_groups")
      expect(out["meta"]).not_to have_key("polyrun_track_files")
    end
  end

  describe ".console_summary" do
    it "computes line percent" do
      blob = {"/a.rb" => {"lines" => [nil, 1, 0, 2]}}
      s = described_class.console_summary(blob)
      expect(s[:lines_relevant]).to eq(3)
      expect(s[:lines_covered]).to eq(2)
      expect(s[:line_percent]).to be > 0
    end

    it "counts legacy raw line arrays" do
      s = described_class.console_summary({"/a.rb" => [nil, 1, 0]})
      expect(s[:lines_relevant]).to eq(2)
      expect(s[:lines_covered]).to eq(1)
    end
  end

  describe ".emit_html" do
    it "includes summary and escaped file paths" do
      html = described_class.emit_html({"/app/a.rb" => {"lines" => [nil, 1, 0]}}, title: "Test")
      expect(html).to include("<!DOCTYPE html>", "Test", "/app/a.rb", "50.00", "<tbody>")
    end
  end

  describe ".emit_lcov" do
    it "emits TN, SF, and DA records (geninfo tracefile shape)" do
      blob = {"/app/a.rb" => {"lines" => [nil, 1, 0]}}
      lcov = described_class.emit_lcov(blob)
      expect(lcov).to include("TN:polyrun\nSF:/app/a.rb")
      expect(lcov).to include("DA:2,1")
      expect(lcov).to include("DA:3,0")
    end
  end
end
