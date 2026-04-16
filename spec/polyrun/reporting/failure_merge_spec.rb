require "spec_helper"
require "json"
require "tmpdir"
require "fileutils"

require "polyrun/reporting/failure_merge"

RSpec.describe Polyrun::Reporting::FailureMerge do
  describe ".merge_files!" do
    it "merges jsonl fragments into one jsonl file" do
      Dir.mktmpdir do |dir|
        a = File.join(dir, "polyrun-failure-fragment-worker0.jsonl")
        b = File.join(dir, "polyrun-failure-fragment-worker1.jsonl")
        File.write(a, JSON.generate({"id" => "a:1", "message" => "x"}) + "\n")
        File.write(b, JSON.generate({"id" => "b:1", "message" => "y"}) + "\n")
        out = File.join(dir, "merged.jsonl")
        n = described_class.merge_files!([a, b], output: out, format: "jsonl")
        expect(n).to eq(2)
        lines = File.read(out).lines.map(&:strip).reject(&:empty?)
        expect(lines.size).to eq(2)
        rows = lines.map { |l| JSON.parse(l) }
        expect(rows.map { |r| r["id"] }).to eq(%w[a:1 b:1])
      end
    end

    it "merges RSpec JSON files into json" do
      Dir.mktmpdir do |dir|
        rs = File.join(dir, "rspec-0.json")
        File.write(rs, JSON.dump({
          "examples" => [
            {"id" => "z", "status" => "passed"},
            {
              "id" => "f1",
              "status" => "failed",
              "full_description" => "x",
              "file_path" => "a_spec.rb",
              "line_number" => 3,
              "exception" => {"message" => "boom", "class" => "RuntimeError"}
            }
          ]
        }))
        out = File.join(dir, "merged.json")
        n = described_class.merge_files!([rs], output: out, format: "json")
        expect(n).to eq(1)
        doc = JSON.parse(File.read(out))
        expect(doc["failures"].size).to eq(1)
        expect(doc["failures"][0]["message"]).to eq("boom")
      end
    end

    it "raises Polyrun::Error with line number on invalid JSONL" do
      Dir.mktmpdir do |dir|
        bad = File.join(dir, "bad.jsonl")
        File.write(bad, "{\"ok\":true}\nNOT JSON\n")
        expect do
          described_class.merge_files!([bad], output: File.join(dir, "out.jsonl"), format: "jsonl")
        end.to raise_error(Polyrun::Error, /line 2/)
      end
    end

    it "raises Polyrun::Error for JSON file that is not RSpec shape" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "other.json")
        File.write(path, JSON.dump({"coverage" => {}}))
        expect do
          described_class.merge_files!([path], output: File.join(dir, "out.json"), format: "json")
        end.to raise_error(Polyrun::Error, /not RSpec JSON/)
      end
    end

    it "raises Polyrun::Error when JSON file is not valid JSON" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "garbage.json")
        File.write(path, "{")
        expect do
          described_class.merge_files!([path], output: File.join(dir, "out.json"), format: "json")
        end.to raise_error(Polyrun::Error, /not valid JSON/)
      end
    end
  end
end
