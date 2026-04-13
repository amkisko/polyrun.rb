require "spec_helper"
require "fileutils"
require "tmpdir"
require "yaml"

RSpec.describe Polyrun::Coverage::Rails do
  describe ".infer_root_from_path" do
    it "returns project root for common test entrypoints" do
      expect(described_class.infer_root_from_path("/app/spec/spec_helper.rb")).to eq("/app")
      expect(described_class.infer_root_from_path("/app/test/test_helper.rb")).to eq("/app")
    end

    it "returns nil for other files" do
      expect(described_class.infer_root_from_path("/app/lib/foo.rb")).to be_nil
    end
  end

  describe ".start!" do
    it "loads config/polyrun_coverage.yml and forwards to Collector.start!" do
      Dir.mktmpdir do |dir|
        config_dir = File.join(dir, "config")
        FileUtils.mkdir_p(config_dir)
        File.write(File.join(config_dir, "polyrun_coverage.yml"), <<~YAML)
          minimum_line_percent: 88
          track_under:
            - lib
        YAML

        expect(Polyrun::Coverage::Collector).to receive(:start!).with(
          hash_including(
            root: dir,
            minimum_line_percent: 88,
            track_under: ["lib"]
          )
        )

        described_class.start!(root: dir)
      end
    end

    it "merges Ruby overrides on top of YAML" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "config"))
        File.write(File.join(dir, "config", "polyrun_coverage.yml"), "minimum_line_percent: 50\n")
        expect(Polyrun::Coverage::Collector).to receive(:start!).with(
          hash_including(minimum_line_percent: 90)
        )
        described_class.start!(root: dir, minimum_line_percent: 90)
      end
    end

    it "builds formatter from report_formats" do
      Dir.mktmpdir do |dir|
        expect(Polyrun::Coverage::Collector).to receive(:start!) do |kwargs|
          expect(kwargs[:formatter]).to be_a(Polyrun::Coverage::Formatter::MultiFormatter)
          expect(kwargs[:report_output_dir]).to eq(File.join(dir, "coverage", "out"))
        end
        described_class.start!(
          root: dir,
          config_path: "/nonexistent.yml",
          report_formats: %w[json html],
          report_output_dir: "coverage/out"
        )
      end
    end
  end
end
