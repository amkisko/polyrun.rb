require "spec_helper"
require "json"

RSpec.describe "observation and measurements" do
  it "records bounded Ruby calls without arguments or outside paths" do
    Dir.mktmpdir do |root|
      script = File.join(root, "probe.rb")
      trace = File.join(root, "trace.json")
      File.write(script, "class Probe; def call(secret); secret.to_s; end; end; 3.times { Probe.new.call('private-value') }")
      output, status = polyrun("observe", "--enable", "--root", root, "--output", trace, "--", Gem.ruby, script)
      expect(status.exitstatus).to eq(0)
      report = JSON.parse(output)
      expect(report["ok"]).to be(true)
      observed = JSON.parse(File.read(trace))
      expect(observed["calls"]).to include(a_hash_including("path" => "probe.rb", "owner" => "Probe", "method" => "call", "count" => 3))
      expect(observed.to_s).not_to include("private-value", root)
    end
  end

  it "bounds unique calls and reports truncation" do
    Dir.mktmpdir do |root|
      script = File.join(root, "probe.rb")
      trace = File.join(root, "trace.json")
      File.write(script, "class Probe; def a; 1; end; def b; 2; end; end; Probe.new.a; Probe.new.b")
      _, status = polyrun("observe", "--enable", "--root", root, "--output", trace, "--max-entries", "1", "--", Gem.ruby, script)
      expect(status.exitstatus).to eq(0)
      observed = JSON.parse(File.read(trace))
      expect(observed["calls"].size).to eq(1)
      expect(observed["truncated"]).to be(true)
    end
  end

  it "identifies instance and singleton subjects without anonymous object identifiers" do
    Dir.mktmpdir do |root|
      script = File.join(root, "probe.rb")
      trace = File.join(root, "trace.json")
      File.write(script, "class Probe; def self.a; 1; end; def b; 2; end; end; Probe.a; Probe.new.b; Class.new { def c; 3; end }.new.c")
      _, status = polyrun("observe", "--enable", "--root", root, "--output", trace, "--", Gem.ruby, script)
      expect(status.exitstatus).to eq(0)
      rows = JSON.parse(File.read(trace))["calls"]
      expect(rows.map { |row| row["subject"] }).to contain_exactly("Probe.a", "Probe#b")
    end
  end

  it "does not mistake an old trace or a non-Ruby process for observed Ruby calls" do
    Dir.mktmpdir do |root|
      trace = File.join(root, "trace.json")
      File.write(trace, '{"calls":[{"count":999}]}')
      output, status = polyrun("observe", "--enable", "--root", root, "--output", trace, "--", "/usr/bin/true")
      expect(status.exitstatus).to eq(1)
      expect(JSON.parse(output)).to include("ok" => false, "code" => "TRACE_MISSING")
      expect(JSON.parse(File.read(trace))["calls"]).to eq([{"count" => 999}])
    end
  end

  it "fails closed on a ceiling for an unavailable measurement" do
    Dir.mktmpdir do |root|
      ceilings = File.join(root, "ceilings.json")
      File.write(ceilings, JSON.generate("child_peak_rss_bytes" => 100_000))
      output, status = polyrun("measure", "--enable", "--ceilings", ceilings, "--", Gem.ruby, "-e", "exit 0")
      expect(status.exitstatus).to eq(1)
      expect(JSON.parse(output)["failures"]).to include("child_peak_rss_bytes")
    end
  end

  it "keeps the parent observation when a forked child exits" do
    Dir.mktmpdir do |root|
      script = File.join(root, "probe.rb")
      trace = File.join(root, "trace.json")
      File.write(script, "class Probe; def self.parent; 1; end; def self.child; 2; end; end; Probe.parent; child = fork { Probe.child; exit }; Process.waitpid(child)")
      output, status = polyrun("observe", "--enable", "--root", root, "--output", trace, "--", Gem.ruby, script)
      expect(status.exitstatus).to eq(0), output
      expect(JSON.parse(File.read(trace))["calls"].map { |row| row["subject"] }).to eq(["Probe.parent"])
    end
  end
end
