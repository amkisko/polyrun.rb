require "spec_helper"
require "fileutils"
require "json"
require "tmpdir"

RSpec.describe "Polyrun::CLI prepare recipes" do
  it "prepare assets runs a custom shell command" do
    Dir.mktmpdir do |dir|
      cfg = File.join(dir, "polyrun.yml")
      File.write(cfg, <<~YAML)
        prepare:
          recipe: assets
          rails_root: #{dir}
          command: printf assets > assets.txt
      YAML
      with_chdir(dir) do
        out, status = polyrun("-c", cfg, "prepare")
        expect(status.success?).to be true
        expect(File.read("assets.txt")).to eq("assets")
        expect(JSON.parse(out)["recipe"]).to eq("assets")
      end
    end
  end

  it "prepare assets exits 1 when custom command fails" do
    Dir.mktmpdir do |dir|
      cfg = File.join(dir, "polyrun.yml")
      File.write(cfg, <<~YAML)
        prepare:
          recipe: assets
          rails_root: #{dir}
          command: exit 1
      YAML
      with_chdir(dir) do
        _out, status = polyrun("-c", cfg, "prepare")
        expect(status.exitstatus).to eq(1)
      end
    end
  end

  it "prepare shell runs multiple commands from prepare.commands" do
    Dir.mktmpdir do |dir|
      cfg = File.join(dir, "polyrun.yml")
      File.write(cfg, <<~YAML)
        prepare:
          recipe: shell
          rails_root: #{dir}
          commands:
            - printf one > step1.txt
            - printf two > step2.txt
      YAML
      with_chdir(dir) do
        out, status = polyrun("-c", cfg, "prepare")
        expect(status.success?).to be true
        expect(File.read("step1.txt")).to eq("one")
        expect(File.read("step2.txt")).to eq("two")
        expect(JSON.parse(out)["actions"].size).to eq(2)
      end
    end
  end

  it "prepare exits 1 for unknown recipe" do
    Dir.mktmpdir do |dir|
      cfg = File.join(dir, "polyrun.yml")
      File.write(cfg, <<~YAML)
        prepare:
          recipe: unknown
      YAML
      with_chdir(dir) do
        _out, status = polyrun("-c", cfg, "prepare")
        expect(status.exitstatus).to eq(1)
      end
    end
  end

  it "prepare assets uses Prepare::Assets when command is omitted" do
    Dir.mktmpdir do |dir|
      cfg = File.join(dir, "polyrun.yml")
      rails = File.join(dir, "bin", "rails")
      FileUtils.mkdir_p(File.dirname(rails))
      File.write(rails, "#!/bin/sh\nexit 0\n")
      FileUtils.chmod(0o755, rails)
      File.write(cfg, <<~YAML)
        prepare:
          recipe: assets
          rails_root: #{dir}
      YAML
      with_chdir(dir) do
        out, status = polyrun("-c", cfg, "prepare")
        expect(status.success?).to be true
        expect(JSON.parse(out)["artifacts"].first).to include("public/assets")
      end
    end
  end

  it "prepare assets dry-run records actions without executing" do
    Dir.mktmpdir do |dir|
      cfg = File.join(dir, "polyrun.yml")
      File.write(cfg, <<~YAML)
        prepare:
          recipe: assets
          rails_root: #{dir}
          command: printf assets > assets.txt
      YAML
      with_chdir(dir) do
        out, status = polyrun("-c", cfg, "prepare", "--dry-run")
        expect(status.success?).to be true
        manifest = JSON.parse(out)
        expect(manifest["executed"]).to be false
        expect(manifest["actions"]).to eq(["printf assets > assets.txt"])
        expect(File.file?("assets.txt")).to be false
      end
    end
  end

  it "prepare shell dry-run lists commands without executing" do
    Dir.mktmpdir do |dir|
      cfg = File.join(dir, "polyrun.yml")
      File.write(cfg, <<~YAML)
        prepare:
          recipe: shell
          rails_root: #{dir}
          commands:
            - printf one > step1.txt
      YAML
      with_chdir(dir) do
        out, status = polyrun("-c", cfg, "prepare", "--dry-run")
        expect(status.success?).to be true
        manifest = JSON.parse(out)
        expect(manifest["executed"]).to be false
        expect(File.file?("step1.txt")).to be false
      end
    end
  end

  it "prepare shell exits 1 when commands are missing" do
    Dir.mktmpdir do |dir|
      cfg = File.join(dir, "polyrun.yml")
      File.write(cfg, <<~YAML)
        prepare:
          recipe: shell
          rails_root: #{dir}
      YAML
      with_chdir(dir) do
        _out, status = polyrun("-c", cfg, "prepare")
        expect(status.exitstatus).to eq(1)
      end
    end
  end

  it "prepare shell exits 1 when a command fails" do
    Dir.mktmpdir do |dir|
      cfg = File.join(dir, "polyrun.yml")
      File.write(cfg, <<~YAML)
        prepare:
          recipe: shell
          rails_root: #{dir}
          commands:
            - printf ok > step.txt
            - exit 2
      YAML
      with_chdir(dir) do
        _out, status = polyrun("-c", cfg, "prepare")
        expect(status.exitstatus).to eq(1)
      end
    end
  end
end
