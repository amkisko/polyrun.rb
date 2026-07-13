require "spec_helper"
require "fileutils"
require "json"
require "tmpdir"

RSpec.describe Polyrun::CLI do
  it "merge-failures command writes json" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        f = File.join(dir, "f.jsonl")
        File.write(f, JSON.generate({"id" => "z", "message" => "m"}) + "\n")
        out = File.join(dir, "out.json")
        _, status = polyrun(
          "merge-failures", "-i", f, "-o", out, "--format", "json"
        )
        expect(status.success?).to be true
        expect(JSON.parse(File.read(out))["failures"].size).to eq(1)
      end
    end
  end

  it "merge-failures command writes csv and markdown" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        f = File.join(dir, "f.jsonl")
        File.write(f, JSON.generate({"id" => "z", "message" => "boom", "full_description" => "fails"}) + "\n")
        csv_out = File.join(dir, "out.csv")
        md_out = File.join(dir, "out.md")
        _, csv_status = polyrun("merge-failures", "-i", f, "-o", csv_out, "--format", "csv")
        _, md_status = polyrun("merge-failures", "-i", f, "-o", md_out, "--format", "markdown")
        expect(csv_status.success?).to be true
        expect(md_status.success?).to be true
        expect(File.read(csv_out)).to include("full_description,location")
        expect(File.read(csv_out)).to include("fails")
        expect(File.read(md_out)).to include("# Polyrun failure report")
        expect(File.read(md_out)).to include("boom")
      end
    end
  end

  it "merge-failures command exits 1 on invalid JSONL" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        f = File.join(dir, "bad.jsonl")
        File.write(f, "not json\n")
        _, status = polyrun(
          "merge-failures", "-i", f, "-o", File.join(dir, "out.jsonl"), "--format", "jsonl"
        )
        expect(status.success?).to be false
        expect(status.exitstatus).to eq(1)
      end
    end
  end
end
