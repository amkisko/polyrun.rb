require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe "polyrun doctor", :aggregate_failures do
  it "bounds its worker and shard summary to the start worker limit" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        File.write("polyrun.yml", <<~YAML)
          workers: 12
          databases:
            template_db: app_template
            shard_db_pattern: "app_test_%{shard}"
            postgresql:
              host: localhost
        YAML

        out, status = polyrun("doctor")

        expect(status.success?).to be true
        expect(out).to include("workers: 10\n")
        expect(out).to include("app_test_9")
        expect(out).not_to include("app_test_10", "app_test_11")
      end
    end
  end

  it "reports the coverage source selected with --config" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        File.write("selected.yml", "coverage:\n  minimum_line_percent: 90\n")

        out, status = polyrun("--config", "selected.yml", "doctor")

        expect(status.success?).to be true
        expect(out).to include("coverage.source: selected.yml")
      end
    end
  end

  it "prints config path, suite, start gates, coverage source, and adapter notes" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        FileUtils.mkdir_p("config")
        File.write("polyrun.yml", <<~YAML)
          version: 1
          workers: 4
          partition:
            paths_file: spec/list.txt
            shard_total: 4
            paths_build:
              all_glob: spec/**/*_spec.rb
          prepare:
            recipe: shell
            command: echo prepare
          start:
            prepare: true
            databases: true
          databases:
            template_db: app_template
            shard_db_pattern: "app_test_%{shard}"
            postgresql:
              host: localhost
          suites:
            unit:
              workers: 2
              partition:
                shard_total: 2
        YAML
        File.write("config/polyrun_coverage.yml", "minimum_line_percent: 80\n")

        out, status = polyrun("--suite", "unit", "doctor")
        expect(status.success?).to be true
        expect(out).to include("config:")
        expect(out).to include("polyrun.yml")
        expect(out).to include("suite: unit")
        expect(out).to include("workers: 2")
        expect(out).to match(/start\.prepare:\s*yes/)
        expect(out).to match(/start\.databases:\s*yes/)
        expect(out).to include("postgresql")
        expect(out).to include("app_test_0")
        expect(out).to include("coverage.source: config/polyrun_coverage.yml")
        expect(out).to include("coverage.disable: no")
      end
    end
  end

  it "warns when matrix shard env and in-process workers are both set" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        File.write("polyrun.yml", "workers: 4\npartition:\n  shard_total: 1\n")
        out, status = polyrun(
          "doctor",
          env: {"POLYRUN_SHARD_TOTAL" => "3", "POLYRUN_WORKERS" => "4"}
        )
        expect(status.success?).to be true
        expect(out).to match(/warn:.*matrix.*workers/i)
      end
    end
  end

  it "notes MySQL as URL shaping only" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        File.write("polyrun.yml", <<~YAML)
          start:
            databases: true
          databases:
            template_db: app_template
            shard_db_pattern: "app_test_%{shard}"
            mysql2:
              host: localhost
        YAML
        out, status = polyrun("doctor")
        expect(status.success?).to be true
        expect(out).to match(/mysql/i)
        expect(out).to match(/URL shaping|urls only|no auto clone/i)
      end
    end
  end
end
