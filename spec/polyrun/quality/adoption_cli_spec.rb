require "spec_helper"
require "json"
require "fileutils"

RSpec.describe "quality CLI" do
  it "indexes project source without an optional executable" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      File.write(File.join(root, "lib/account.rb"), "class Account; def save; true; end; end")
      output, status = polyrun("graph", "--enable", "index", "--root", root, "--json", env: {"PATH" => File.dirname(Gem.ruby)})
      expect(status.exitstatus).to eq(0), output
      expect(JSON.parse(output)).to include("ok" => true, "reused" => false)
    end
  end

  it "rejects an unsupported graph command with a JSON diagnostic" do
    output, status = polyrun("graph", "--enable", "unsupported", "--json")
    expect(status.exitstatus).to eq(2)
    expect(JSON.parse(output)).to include("ok" => false, "code" => "INVALID_ARGUMENT")
  end

  it "measures an arbitrary command and preserves its failed status" do
    output, status = polyrun("measure", "--enable", "--label", "probe", "--", Gem.ruby, "-e", "exit 9")
    report = JSON.parse(output)
    expect(status.exitstatus).to eq(9)
    expect(report).to include("label" => "probe", "exitstatus" => 9, "ok" => false)
    expect(report.dig("metrics", "wall_s")).to be > 0
    expect(report.dig("metrics", "child_cpu_s")).to be >= 0
  end

  it "rejects empty mutation selection and unknown options without a traceback" do
    output, status = polyrun("mutate", "--enable")
    expect(status.exitstatus).to eq(2)
    expect(output).to include("subject")
    output, status = polyrun("mutate", "--enable", "--bogus")
    expect(status.exitstatus).to eq(2)
    expect(output).to include("invalid option")
  end

  it "selects file and observed subjects, shards them, and writes its native mutation report" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      File.write(File.join(root, "lib/account.rb"), "class Account; def save; 1; end; end; class Invoice; def save; 2; end; end; class Ledger; def self.find; 3; end; end")
      File.write(File.join(root, "probe.rb"), "require 'account'; abort unless Account.new.save == 1 && Invoice.new.save == 2 && Ledger.find == 3")
      subjects = File.join(root, "subjects.txt")
      observed = File.join(root, "observed.json")
      report_path = File.join(root, "report.json")
      File.write(subjects, "Account#save\nInvoice#save\n")
      File.write(observed, JSON.generate("provenance" => "observed", "calls" => [{"subject" => "Ledger.find"}]))
      output, status = polyrun("mutate", "--enable", "--root", root, "--subjects-file", subjects, "--observed", observed,
        "--shard", "1", "--total", "2", "--workers", "2", "--output", report_path, "--", Gem.ruby, "-Ilib", "probe.rb")
      expect(status.exitstatus).to eq(0), output
      report = JSON.parse(output)
      expect(report).to include("ok" => true, "engine" => "polyrun", "subjects" => ["Account#save", "Ledger.find"], "survived" => 0)
      expect(report["killed"]).to be > 0
      expect(JSON.parse(File.read(report_path))).to eq(report)
    end
  end

  it "reports ambiguous graph selections with a failure status" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      File.write(File.join(root, "lib/account.rb"), "class Account; def save; 1; end; end; class Invoice; def save; 2; end; end")
      polyrun("graph", "--enable", "index", "--root", root, "--json")
      output, status = polyrun("graph", "--enable", "inspect", "save", "--root", root, "--json")
      expect(status.exitstatus).to eq(1)
      expect(JSON.parse(output)).to include("ok" => false, "code" => "AMBIGUOUS_NODE")
    end
  end
end
