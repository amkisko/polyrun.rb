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
end
