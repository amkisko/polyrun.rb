require "spec_helper"
require "fileutils"
require "json"
require "tmpdir"

RSpec.describe Polyrun::CLI do
  it "queue reclaim returns paths to pending" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        list = File.join(dir, "spec_paths.txt")
        File.write(list, "a.rb\n")
        polyrun("queue", "init", "--paths-file", list, "--dir", ".polyrun-queue")
        polyrun("queue", "claim", "--dir", ".polyrun-queue", "--worker", "w1", "--batch", "1")
        out, status = polyrun("queue", "reclaim", "--dir", ".polyrun-queue", "--worker", "w1")
        expect(status.success?).to be true
        expect(JSON.parse(out)["reclaimed_paths"]).to eq(1)
      end
    end
  end

  it "queue reclaim exits 2 without --older-than or --worker" do
    out, status = polyrun("queue", "reclaim")
    expect(status.exitstatus).to eq(2)
    expect(out).to include("need --older-than or --worker")
  end

  it "queue ack exits 2 without --lease" do
    out, status = polyrun("queue", "ack")
    expect(status.exitstatus).to eq(2)
    expect(out).to include("need --lease")
  end

  it "queue unknown subcommand prints usage" do
    out, status = polyrun("queue", "nope")
    expect(status.exitstatus).to eq(2)
    expect(out).to include("usage: polyrun queue")
  end

  it "queue status --json includes lease details" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        list = File.join(dir, "spec_paths.txt")
        File.write(list, "a.rb\n")
        polyrun("queue", "init", "--paths-file", list, "--dir", ".polyrun-queue")
        polyrun("queue", "claim", "--dir", ".polyrun-queue", "--batch", "1")
        out, status = polyrun("queue", "status", "--dir", ".polyrun-queue", "--json")
        expect(status.success?).to be true
        parsed = JSON.parse(out)
        expect(parsed["lease_details"]).to be_a(Array)
      end
    end
  end
end
