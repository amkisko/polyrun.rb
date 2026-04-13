require "spec_helper"
require "fileutils"
require "open3"
require "json"
require "tmpdir"
require "rbconfig"

RSpec.describe Polyrun::CLI do
  it "prepare default recipe succeeds" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        out, status = polyrun("prepare")
        expect(status.success?).to be true
        j = JSON.parse(out)
        expect(j["recipe"]).to eq("default")
        expect(j["executed"]).to be true
        expect(j["artifact_manifest_path"]).to end_with("polyrun-artifacts.json")
        expect(File).to exist(File.join(dir, "polyrun-artifacts.json"))
      end
    end
  end

  it "prepare dry-run marks executed false" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        out, status = polyrun("prepare", "--dry-run")
        expect(status.success?).to be true
        expect(JSON.parse(out)["executed"]).to be false
      end
    end
  end

  it "prepare assets dry-run lists planned action" do
    Dir.mktmpdir do |dir|
      cfg = File.join(dir, "polyrun.yml")
      File.write(cfg, <<~YAML)
        prepare:
          recipe: assets
          rails_root: #{dir}
      YAML
      Dir.chdir(dir) do
        out, status = polyrun("-c", cfg, "prepare", "--dry-run")
        expect(status.success?).to be true
        j = JSON.parse(out)
        expect(j["recipe"]).to eq("assets")
        expect(j["actions"]).to include("bin/rails assets:precompile")
      end
    end
  end

  it "prepare assets dry-run lists custom command when prepare.command set" do
    Dir.mktmpdir do |dir|
      cfg = File.join(dir, "polyrun.yml")
      File.write(cfg, <<~YAML)
        prepare:
          recipe: assets
          rails_root: #{dir}
          command: NODENV_VERSION=20 bin/rails assets:precompile
      YAML
      Dir.chdir(dir) do
        out, status = polyrun("-c", cfg, "prepare", "--dry-run")
        expect(status.success?).to be true
        j = JSON.parse(out)
        expect(j["actions"].join).to include("NODENV_VERSION=20")
      end
    end
  end

  it "prepare shell dry-run lists command" do
    Dir.mktmpdir do |dir|
      cfg = File.join(dir, "polyrun.yml")
      File.write(cfg, <<~YAML)
        prepare:
          recipe: shell
          rails_root: #{dir}
          command: echo hello
      YAML
      Dir.chdir(dir) do
        out, status = polyrun("-c", cfg, "prepare", "--dry-run")
        expect(status.success?).to be true
        j = JSON.parse(out)
        expect(j["recipe"]).to eq("shell")
        expect(j["actions"]).to include("echo hello")
      end
    end
  end
end
