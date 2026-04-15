require "spec_helper"
require "fileutils"
require "open3"
require "json"
require "tmpdir"
require "rbconfig"

RSpec.describe Polyrun::CLI do
  it "merges coverage files" do
    Dir.mktmpdir do |dir|
      a = File.join(dir, "a.json")
      b = File.join(dir, "b.json")
      out = File.join(dir, "merged.json")
      File.write(a, JSON.dump({"coverage" => {"/x.rb" => {"lines" => [nil, 1]}}}))
      File.write(b, JSON.dump({"coverage" => {"/x.rb" => {"lines" => [nil, 2]}}}))
      _, status = polyrun("merge-coverage", "-i", a, "-i", b, "-o", out, "--format", "json,lcov")
      expect(status.success?).to be true
      merged = JSON.parse(File.read(out))
      expect(merged["coverage"]["/x.rb"]["lines"]).to eq([nil, 3])
      expect(File).to exist(out.sub(".json", ".lcov"))
    end
  end

  it "fails merge-coverage without inputs" do
    out, status = polyrun("merge-coverage")
    expect(status.success?).to be false
    expect(out).to match(/need at least one existing -i FILE/)
  end

  it "merge-coverage expands globs for -i" do
    Dir.mktmpdir do |dir|
      a = File.join(dir, "polyrun-fragment-0.json")
      b = File.join(dir, "polyrun-fragment-1.json")
      File.write(a, JSON.dump({"coverage" => {"/x.rb" => {"lines" => [nil, 1]}}}))
      File.write(b, JSON.dump({"coverage" => {"/x.rb" => {"lines" => [nil, 2]}}}))
      pattern = File.join(dir, "polyrun-fragment-*.json")
      with_chdir(dir) do
        _, status = polyrun("merge-coverage", "-i", pattern, "-o", "merged.json", "--format", "json")
        expect(status.success?).to be true
        merged = JSON.parse(File.read(File.join(dir, "merged.json")))
        expect(merged["coverage"]["/x.rb"]["lines"]).to eq([nil, 3])
      end
    end
  end

  it "merge-coverage globs include N×M fragment names (shard*-worker*)" do
    Dir.mktmpdir do |dir|
      a = File.join(dir, "polyrun-fragment-shard0-worker0.json")
      b = File.join(dir, "polyrun-fragment-shard0-worker1.json")
      File.write(a, JSON.dump({"coverage" => {"/y.rb" => {"lines" => [nil, 1]}}}))
      File.write(b, JSON.dump({"coverage" => {"/y.rb" => {"lines" => [nil, 0]}}}))
      pattern = File.join(dir, "polyrun-fragment-*.json")
      with_chdir(dir) do
        _, status = polyrun("merge-coverage", "-i", pattern, "-o", "merged.json", "--format", "json")
        expect(status.success?).to be true
        merged = JSON.parse(File.read(File.join(dir, "merged.json")))
        expect(merged["coverage"]["/y.rb"]["lines"]).to eq([nil, 1])
      end
    end
  end

  it "report-coverage writes multiple artifacts" do
    Dir.mktmpdir do |dir|
      j = File.join(dir, "in.json")
      File.write(j, JSON.dump({"coverage" => {"/z.rb" => {"lines" => [1]}}}))
      outd = File.join(dir, "out")
      out, status = polyrun("report-coverage", "-i", j, "-o", outd, "--basename", "cov", "--format", "json,console")
      expect(status.success?).to be true
      meta = JSON.parse(out)
      expect(File).to exist(meta["json"])
      expect(File).to exist(meta["console"])
    end
  end

  it "writes cobertura when requested" do
    Dir.mktmpdir do |dir|
      a = File.join(dir, "a.json")
      out = File.join(dir, "out.json")
      File.write(a, JSON.dump({"coverage" => {"/x.rb" => {"lines" => [nil, 1]}}}))
      _, status = polyrun("merge-coverage", "-i", a, "-o", out, "--format", "json,cobertura")
      expect(status.success?).to be true
      cob = out.sub(/\.json\z/, ".xml")
      cob = "#{out}.cobertura.xml" if cob == out
      expect(File).to exist(cob)
      expect(File.read(cob)).to include("<coverage", "/x.rb")
    end
  end

  it "merge-coverage writes console summary when requested" do
    Dir.mktmpdir do |dir|
      a = File.join(dir, "a.json")
      out = File.join(dir, "out.json")
      File.write(a, JSON.dump({"coverage" => {"/x.rb" => {"lines" => [1]}}}))
      stdout, status = polyrun("merge-coverage", "-i", a, "-o", out, "--format", "json,console")
      expect(status.success?).to be true
      sum = out.sub(/\.json\z/, "-summary.txt")
      sum = "#{out}-summary.txt" if sum == out
      expect(File).to exist(sum)
      expect(File.read(sum)).to include("Polyrun coverage summary")
      expect(stdout).to include("Polyrun coverage summary")
    end
  end

  it "report-coverage writes all default format files" do
    Dir.mktmpdir do |dir|
      j = File.join(dir, "in.json")
      File.write(j, JSON.dump({"coverage" => {"/z.rb" => {"lines" => [1]}}}))
      outd = File.join(dir, "out")
      _, status = polyrun("report-coverage", "-i", j, "-o", outd, "--basename", "full", "--format", "json,lcov,cobertura,console,html")
      expect(status.success?).to be true
      expect(File).to exist(File.join(outd, "full.json"))
      expect(File).to exist(File.join(outd, "full.lcov"))
      expect(File).to exist(File.join(outd, "full.xml"))
      expect(File).to exist(File.join(outd, "full-summary.txt"))
      expect(File).to exist(File.join(outd, "full.html"))
    end
  end
end
