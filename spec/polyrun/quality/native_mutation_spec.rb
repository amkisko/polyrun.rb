require "spec_helper"
require "json"
require "fileutils"

RSpec.describe "Polyrun mutation testing" do
  around do |example|
    Dir.mktmpdir do |root|
      @root = root
      FileUtils.mkdir_p(File.join(root, "lib"))
      @source = "class Account; def self.value; 2; end; end"
      File.write(File.join(root, "lib/account.rb"), @source)
      File.write(File.join(root, "probe.rb"), "require 'account'; abort 'wrong result' unless Account.value == 2")
      example.run
    end
  end

  def mutate(*arguments, probe: "probe.rb")
    output, status = polyrun("mutate", "--enable", "--root", @root, "--subject", "Account.value", *arguments, "--", Gem.ruby, "-Ilib", probe)
    [JSON.parse(output), status]
  end

  it "generates and tests its own mutations in isolation without an installed engine" do
    report, status = mutate("--workers", "2")
    expect(status.exitstatus).to eq(0), report.inspect
    expect(report).to include("ok" => true, "engine" => "polyrun", "survived" => 0)
    expect(report["mutations"]).to be > 0
    expect(report["killed"]).to eq(report["mutations"])
    expect(File.read(File.join(@root, "lib/account.rb"))).to eq(@source)
  end

  it "reports surviving mutations when assertions do not distinguish the changed code" do
    File.write(File.join(@root, "weak.rb"), "require 'account'; Account.value")
    report, status = mutate(probe: "weak.rb")
    expect(status.exitstatus).to eq(1)
    expect(report["survived"]).to eq(report["mutations"])
    expect(report["killed"]).to eq(0)
  end

  it "refuses a failed baseline rather than reporting every mutation killed" do
    File.write(File.join(@root, "broken.rb"), "abort 'broken original'")
    report, status = mutate(probe: "broken.rb")
    expect(status.exitstatus).to eq(1)
    expect(report).to include("code" => "BASELINE_FAILED", "killed" => nil, "survived" => nil)
  end

  it "reports timed out mutations as incomplete rather than killed" do
    File.write(File.join(@root, "slow.rb"), "require 'account'; sleep 10 unless Account.value == 2")
    report, status = mutate("--timeout", "0.2", probe: "slow.rb")
    expect(status.exitstatus).to eq(1)
    expect(report["results"].map { |row| row["code"] }).to include("TIMEOUT")
    expect(report["killed"]).to be_nil
  end
end
