require "spec_helper"
require "tmpdir"
require "json"

RSpec.describe "polyrun --suite", :aggregate_failures do
  it "limits --suite to one CLI invocation in the same process" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        File.write("polyrun.yml", <<~YAML)
          workers: 5
          suites:
            unit:
              workers: 2
        YAML

        selected, selected_status = polyrun("--suite", "unit", "config", "workers", in_process: true)
        base, base_status = polyrun("config", "workers", in_process: true)

        expect(selected_status.success?).to be true
        expect(selected.chomp).to eq("2")
        expect(base_status.success?).to be true
        expect(base.chomp).to eq("5")
      end
    end
  end

  ["--suite", "--suite="].each do |option|
    it "rejects #{option} without a name before starting prepare or workers" do
      Dir.mktmpdir do |dir|
        with_chdir(dir) do
          File.write("polyrun.yml", <<~YAML)
            workers: 1
            prepare:
              recipe: shell
              command: touch prepared.marker
          YAML

          out, status = polyrun(option)

          expect(status.exitstatus).to eq(2)
          expect(out).to include("--suite requires a name")
          expect(File.exist?("prepared.marker")).to be false
        end
      end
    end
  end

  it "selects a named suite for polyrun config workers" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        File.write("polyrun.yml", <<~YAML)
          workers: 5
          partition:
            paths_file: spec/list.txt
            shard_total: 4
          suites:
            unit:
              workers: 2
              partition:
                shard_total: 2
        YAML
        out, status = polyrun("--suite", "unit", "config", "workers")
        expect(status.success?).to be true
        expect(out.chomp).to eq("2")

        out2, status2 = polyrun("--suite", "unit", "config", "partition.shard_total")
        expect(status2.success?).to be true
        expect(out2.chomp).to eq("2")
      end
    end
  end

  it "fails when suite name is unknown" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        File.write("polyrun.yml", <<~YAML)
          suites:
            unit:
              workers: 1
        YAML
        out, status = polyrun("--suite", "nope", "config", "workers")
        expect(status.success?).to be false
        expect(out).to include("unknown suite")
      end
    end
  end
end
