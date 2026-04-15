require "spec_helper"

RSpec.describe "Polyrun::CLI config" do
  it "prints merged prepare.env key (yaml overrides process env, matching prepare)" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        File.write("polyrun.yml", <<~YAML)
          prepare:
            recipe: shell
            env:
              PLAYWRIGHT_ENV: from_yaml
        YAML
        ENV["PLAYWRIGHT_ENV"] = "from_process"
        out, status = polyrun("config", "prepare.env.PLAYWRIGHT_ENV")
        ENV.delete("PLAYWRIGHT_ENV")

        expect(status.success?).to be true
        expect(out.chomp).to eq("from_yaml")
      end
    end
  end

  it "prints prepare.env key from process env when not in yaml" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        File.write("polyrun.yml", <<~YAML)
          prepare:
            recipe: default
        YAML
        ENV["ONLY_ENV"] = "x"
        out, status = polyrun("config", "prepare.env.ONLY_ENV")
        ENV.delete("ONLY_ENV")

        expect(status.success?).to be true
        expect(out.chomp).to eq("x")
      end
    end
  end

  it "prints yaml-only dotted path" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        File.write("polyrun.yml", <<~YAML)
          partition:
            paths_file: spec/spec_paths.txt
        YAML
        out, status = polyrun("config", "partition.paths_file")
        expect(status.success?).to be true
        expect(out.chomp).to eq("spec/spec_paths.txt")
      end
    end
  end

  it "fails when path has no value" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        File.write("polyrun.yml", "partition: {}\n")
        _out, status = polyrun("config", "partition.nope")
        expect(status.exitstatus).to eq(1)
      end
    end
  end

  it "fails when prepare.env key is absent from env and yaml" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        File.write("polyrun.yml", <<~YAML)
          prepare:
            env: {}
        YAML
        _out, status = polyrun("config", "prepare.env.MISSING_KEY_XYZ")
        expect(status.exitstatus).to eq(1)
      end
    end
  end

  it "prints effective partition.shard_index as integer" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        File.write("polyrun.yml", <<~YAML)
          partition:
            shard_index: 2
        YAML
        out, status = polyrun("config", "partition.shard_index")
        expect(status.success?).to be true
        expect(out.chomp).to match(/\A\d+\z/)
      end
    end
  end
end
