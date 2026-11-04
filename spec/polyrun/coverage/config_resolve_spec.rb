require "spec_helper"
require "fileutils"
require "tmpdir"
require "yaml"

RSpec.describe Polyrun::Coverage::ConfigResolve do
  describe ".load" do
    it "uses coverage from the selected suite in the active config" do
      original_suite = ENV["POLYRUN_SUITE"]
      ENV["POLYRUN_SUITE"] = "unit"
      Dir.mktmpdir do |dir|
        path = File.join(dir, "selected.yml")
        File.write(path, <<~YAML)
          coverage:
            minimum_line_percent: 10
            track_under: [lib]
          suites:
            unit:
              coverage:
                minimum_line_percent: 90
                formats: [json]
        YAML

        cfg = described_class.load(root: dir, polyrun_config_path: path)

        expect(cfg["minimum_line_percent"]).to eq(90)
        expect(cfg["track_under"]).to eq(["lib"])
        expect(cfg["report_formats"]).to eq(["json"])
      end
    ensure
      ENV["POLYRUN_SUITE"] = original_suite
    end

    it "uses inline coverage from polyrun.yml when polyrun_coverage.yml is absent" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "polyrun.yml"), <<~YAML)
          coverage:
            minimum_line_percent: 77
            track_under:
              - lib
              - app
            formats:
              - json
              - html
            output_path: coverage
        YAML

        cfg = described_class.load(root: dir)
        expect(cfg["minimum_line_percent"]).to eq(77)
        expect(cfg["track_under"]).to eq(%w[lib app])
        expect(cfg["report_formats"]).to eq(%w[json html])
        expect(cfg["report_output_dir"]).to eq(File.join(dir, "coverage"))
        expect(cfg["coverage_config_source"]).to eq("polyrun.yml")
      end
    end

    it "prefers config/polyrun_coverage.yml over inline coverage" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "config"))
        File.write(File.join(dir, "polyrun.yml"), <<~YAML)
          coverage:
            minimum_line_percent: 10
            track_under:
              - stale
        YAML
        File.write(File.join(dir, "config", "polyrun_coverage.yml"), <<~YAML)
          minimum_line_percent: 90
          track_under:
            - lib
        YAML

        cfg = described_class.load(root: dir)
        expect(cfg["minimum_line_percent"]).to eq(90)
        expect(cfg["track_under"]).to eq(["lib"])
        expect(cfg["coverage_config_source"]).to eq("config/polyrun_coverage.yml")
      end
    end

    it "ignores inline coverage keys when the coverage file is present" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "config"))
        File.write(File.join(dir, "polyrun.yml"), <<~YAML)
          coverage:
            minimum_line_percent: 10
            reject_patterns:
              - "/vendor/"
            track_under:
              - lib
        YAML
        File.write(File.join(dir, "config", "polyrun_coverage.yml"), <<~YAML)
          minimum_line_percent: 88
          track_under:
            - app
        YAML

        cfg = described_class.load(root: dir)
        expect(cfg["minimum_line_percent"]).to eq(88)
        expect(cfg["track_under"]).to eq(["app"])
        expect(cfg["reject_patterns"]).to be_nil
        expect(cfg["coverage_config_source"]).to eq("config/polyrun_coverage.yml")
      end
    end
  end
end
