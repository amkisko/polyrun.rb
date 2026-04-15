require "spec_helper"
require "fileutils"
require "open3"
require "json"
require "tmpdir"
require "rbconfig"

RSpec.describe Polyrun::CLI do
  it "prints version" do
    out, status = polyrun("version")
    expect(status.success?).to be true
    expect(out).to include(Polyrun::VERSION)
    expect(out.lines.map(&:chomp)).to eq(["polyrun #{Polyrun::VERSION}"])
  end

  it "init --list prints profiles" do
    out, status = polyrun("init", "--list")
    expect(status.success?).to be true
    expect(out).to include("gem")
    expect(out).to include("minimal_gem.polyrun.yml")
  end

  it "init writes polyrun.yml from gem profile" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        _out, status = polyrun("init", "--profile", "gem", "-o", "polyrun.yml")
        expect(status.success?).to be true
        expect(File.read("polyrun.yml")).to include("paths_file: spec/spec_paths.txt")
      end
    end
  end

  it "init refuses overwrite without --force" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        File.write("polyrun.yml", "x")
        _out, status = polyrun("init", "--profile", "gem")
        expect(status.success?).to be false
      end
    end
  end

  it "init --dry-run does not write" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        out, status = polyrun("init", "--profile", "gem", "--dry-run")
        expect(status.success?).to be true
        expect(out).to include("paths_file:")
        expect(File.file?("polyrun.yml")).to be false
      end
    end
  end

  it "fails unknown command" do
    out, status = polyrun("nope")
    expect(status.exitstatus).to eq(2)
    expect(out).to match(/unknown command/)
  end

  it "prints help with -h" do
    out, status = polyrun("-h")
    expect(status.success?).to be true
    expect(out).to include("db:clone-shards")
    expect(out).to include("parallel-rspec")
    expect(out).to include("merge-coverage")
    expect(out).to include("config")
    expect(out).to include("merge-timing")
    expect(out).to include("report-junit")
    expect(out).to include("report-timing")
    expect(out).to include("POLYRUN_DEBUG")
    expect(out).to include("POLYRUN_MERGE_FORMATS")
    expect(out).to include("start")
    expect(out).to include("build-paths")
    expect(out).to include("ci-shard-run")
    expect(out).to include("ci-shard-rspec")
    expect(out).to include("POLYRUN_SKIP_BUILD_SPEC_PATHS")
    expect(out).to include("POLYRUN_SKIP_PATHS_BUILD")
    expect(out).to include("POLYRUN_MERGE_SLOW_WARN_SECONDS")
    expect(out).to include("POLYRUN_COVERAGE_BRANCHES")
    expect(out).to include("init")
  end
end
