require "spec_helper"
require "fileutils"
require "json"
require "tmpdir"

RSpec.describe Polyrun::CLI do
  it "report-timing writes output file when -o is set" do
    Dir.mktmpdir do |dir|
      f = File.join(dir, "polyrun_timing.json")
      out_path = File.join(dir, "summary.txt")
      File.write(f, JSON.dump({"/a.rb" => 2.0}))
      out, status = polyrun("report-timing", "-i", f, "-o", out_path)
      expect(status.success?).to be true
      expect(out.strip).to eq(File.expand_path(out_path))
      expect(File.read(out_path)).to include("/a.rb")
    end
  end

  it "report-junit exits 2 when input file is missing" do
    out, status = polyrun("report-junit", "-i", "/no/such/rspec.json")
    expect(status.exitstatus).to eq(2)
    expect(out).to include("not a file")
  end

  it "report-junit merges multiple inputs" do
    Dir.mktmpdir do |dir|
      a = File.join(dir, "a.json")
      b = File.join(dir, "b.json")
      File.write(a, JSON.dump({"examples" => [{"description" => "a", "full_description" => "g a", "file_path" => "./a.rb", "status" => "passed", "run_time" => 0.01}]}))
      File.write(b, JSON.dump({"examples" => [{"description" => "b", "full_description" => "g b", "file_path" => "./b.rb", "status" => "failed", "run_time" => 0.02}]}))
      out, status = polyrun("report-junit", "-i", a, "-i", b)
      expect(status.success?).to be true
      xml = File.read(out.strip)
      expect(xml).to include("a")
      expect(xml).to include("b")
    end
  end

  it "report-junit writes CSV and Markdown exports" do
    Dir.mktmpdir do |dir|
      inp = File.join(dir, "rspec.json")
      csv_out = File.join(dir, "junit.csv")
      md_out = File.join(dir, "junit.md")
      File.write(inp, JSON.dump({
        "examples" => [
          {"full_description" => "Foo passes", "file_path" => "./spec/a.rb", "status" => "passed", "run_time" => 0.01},
          {"full_description" => "Foo fails", "file_path" => "./spec/a.rb", "status" => "failed", "run_time" => 0.02, "exception" => {"message" => "boom"}}
        ]
      }))
      _, csv_status = polyrun("report-junit", "-i", inp, "-o", csv_out, "--format", "csv")
      _, md_status = polyrun("report-junit", "-i", inp, "-o", md_out, "--format", "markdown")
      expect(csv_status.success?).to be true
      expect(md_status.success?).to be true
      expect(File.read(csv_out)).to include("classname,name,status")
      expect(File.read(csv_out)).to include("Foo fails")
      expect(File.read(md_out)).to include("## Failures")
      expect(File.read(md_out)).to include("boom")
    end
  end

  it "report-benchmark exports profile JSON to CSV" do
    Dir.mktmpdir do |dir|
      profile = File.join(dir, "profile.json")
      out = File.join(dir, "profile.csv")
      File.write(profile, JSON.dump({
        "meta" => {"commit" => "abc", "recorded_at" => "2026-07-13T12:00:00Z", "ruby" => RUBY_VERSION},
        "lines" => ["line"],
        "metrics" => [{"section" => "merge", "name" => "merge_two", "value" => 0.1, "unit" => "seconds"}]
      }))
      _, status = polyrun("report-benchmark", "-i", profile, "-o", out, "--format", "csv")
      expect(status.success?).to be true
      expect(File.read(out)).to include("merge_two")
    end
  end
end
