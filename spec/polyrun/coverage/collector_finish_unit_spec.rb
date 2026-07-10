require "spec_helper"
require "tmpdir"

RSpec.describe "Polyrun::Coverage::Collector finish helpers" do
  def with_collector_config(config)
    collector = Polyrun::Coverage::Collector
    had_config = collector.instance_variable_defined?(:@config)
    saved_config = had_config ? collector.instance_variable_get(:@config) : nil
    collector.instance_variable_set(:@config, config)
    yield
  ensure
    if had_config
      collector.instance_variable_set(:@config, saved_config)
    elsif collector.instance_variable_defined?(:@config)
      collector.remove_instance_variable(:@config)
    end
  end

  describe ".send(:prepare_finish_blob)" do
    it "normalizes coverage, applies track_under, and rejects patterns" do
      Dir.mktmpdir do |root|
        kept = File.join(root, "lib", "kept.rb")
        dropped = File.join(root, "lib", "reporting", "rspec_junit.rb")
        FileUtils.mkdir_p(File.dirname(dropped))
        File.write(kept, "KEPT = 1\n")
        File.write(dropped, "DROPPED = 1\n")
        cfg = {
          root: root,
          track_under: ["lib"],
          track_files: nil,
          reject_patterns: ["/reporting/rspec_junit.rb"]
        }
        raw = {
          kept => {lines: [nil, 1]},
          dropped => {lines: [nil, 1]},
          "/outside/other.rb" => {lines: [1]}
        }
        allow(Coverage).to receive(:result).and_return(raw)
        blob = Polyrun::Coverage::Collector.send(:prepare_finish_blob, cfg)
        expect(blob.keys).to eq([kept])
      end
    end
  end

  describe ".send(:track_blob_for_finish)" do
    around do |example|
      old_total = ENV["POLYRUN_SHARD_TOTAL"]
      example.run
      old_total ? ENV.store("POLYRUN_SHARD_TOTAL", old_total) : ENV.delete("POLYRUN_SHARD_TOTAL")
    end

    it "merges untracked files on a single shard when track_files is set" do
      Dir.mktmpdir do |root|
        loaded = File.join(root, "lib", "loaded.rb")
        unloaded = File.join(root, "lib", "unloaded.rb")
        FileUtils.mkdir_p(File.dirname(loaded))
        File.write(loaded, "LOADED = 1\n")
        File.write(unloaded, "UNLOADED = 1\n")
        cfg = {root: root, track_files: ["lib/**/*.rb"], track_under: ["lib"]}
        blob = {loaded => {"lines" => [nil, 1]}}
        ENV["POLYRUN_SHARD_TOTAL"] = "1"
        out = Polyrun::Coverage::Collector.send(:track_blob_for_finish, cfg, blob)
        expect(out.keys.sort).to eq([loaded, unloaded].sort)
      end
    end

    it "keeps only loaded tracked files when sharded" do
      Dir.mktmpdir do |root|
        loaded = File.join(root, "lib", "loaded.rb")
        unloaded = File.join(root, "lib", "unloaded.rb")
        FileUtils.mkdir_p(File.dirname(loaded))
        File.write(loaded, "LOADED = 1\n")
        File.write(unloaded, "UNLOADED = 1\n")
        cfg = {root: root, track_files: ["lib/**/*.rb"], track_under: ["lib"]}
        blob = {loaded => {"lines" => [nil, 1]}}
        ENV["POLYRUN_SHARD_TOTAL"] = "3"
        out = Polyrun::Coverage::Collector.send(:track_blob_for_finish, cfg, blob)
        expect(out.keys).to eq([loaded])
      end
    end
  end

  describe ".send(:write_finish_fragment!)" do
    it "writes merge-compatible JSON to the configured output path" do
      Dir.mktmpdir do |root|
        output_path = File.join(root, "coverage", "frag.json")
        cfg = {root: root, output_path: output_path, meta: {}, fragment_meta: {}}
        blob = {File.join(root, "lib", "x.rb") => {"lines" => [1]}}
        Polyrun::Coverage::Collector.send(:write_finish_fragment!, cfg, blob, nil)
        payload = JSON.parse(File.read(output_path))
        expect(payload.fetch("coverage")).to have_key(File.join(root, "lib", "x.rb"))
      end
    end
  end

  describe ".send(:run_finish_formatter!)" do
    around do |example|
      old_total = ENV["POLYRUN_SHARD_TOTAL"]
      example.run
      old_total ? ENV.store("POLYRUN_SHARD_TOTAL", old_total) : ENV.delete("POLYRUN_SHARD_TOTAL")
    end

    it "runs the formatter on a single shard and post-processes Cobertura XML" do
      Dir.mktmpdir do |root|
        report_directory = File.join(root, "coverage", "reports")
        cfg = {
          root: root,
          formatter: Class.new do
            define_method(:format) do |_result, output_dir:, basename:|
              FileUtils.mkdir_p(output_dir)
              File.write(File.join(output_dir, "#{basename}.xml"), "<coverage/>")
            end
          end.new,
          report_output_dir: report_directory,
          report_basename: "worker-coverage",
          meta: {},
          fragment_meta: {}
        }
        blob = {File.join(root, "lib", "x.rb") => {"lines" => [1]}}
        ENV["POLYRUN_SHARD_TOTAL"] = "1"
        Polyrun::Coverage::Collector.send(:run_finish_formatter!, cfg, blob, nil)
        expect(File).to exist(File.join(report_directory, "worker-coverage.xml"))
      end
    end

    it "skips per-worker formatter output when sharded" do
      Dir.mktmpdir do |root|
        cfg = {
          root: root,
          formatter: Class.new do
            define_method(:format) do |_result, output_dir:, basename:|
              FileUtils.mkdir_p(output_dir)
              File.write(File.join(output_dir, "#{basename}-marker.txt"), "formatted")
            end
          end.new,
          meta: {},
          fragment_meta: {}
        }
        blob = {File.join(root, "lib", "x.rb") => {"lines" => [1]}}
        ENV["POLYRUN_SHARD_TOTAL"] = "2"
        expect(Polyrun::Debug).to receive(:log_worker).with(/skipping per-worker formatter/)
        Polyrun::Coverage::Collector.send(:run_finish_formatter!, cfg, blob, nil)
        expect(Dir.glob(File.join(root, "**", "*-marker.txt"))).to be_empty
      end
    end
  end

  describe ".send(:exit_if_below_minimum_line_percent)" do
    it "warns without exiting when strict is false" do
      cfg = {minimum_line_percent: 99, strict: false, shard_total_at_start: 1}
      summary = {line_percent: 10.0, lines_covered: 1, lines_relevant: 10, files: 1}
      expect(Polyrun::Log).to receive(:warn).at_least(:once)
      expect { Polyrun::Coverage::Collector.send(:exit_if_below_minimum_line_percent, cfg, summary) }.not_to raise_error
    end

    it "does not gate per-worker fragments when shard_total_at_start > 1" do
      cfg = {minimum_line_percent: 99, strict: true, shard_total_at_start: 5}
      expect(Polyrun::Log).not_to receive(:warn)
      Polyrun::Coverage::Collector.send(:exit_if_below_minimum_line_percent, cfg, {line_percent: 0})
    end
  end

  describe ".finish" do
    around do |example|
      keys = %w[POLYRUN_SHARD_TOTAL POLYRUN_COVERAGE_VERBOSE]
      old = keys.to_h { |key| [key, ENV[key]] }
      keys.each { |key| ENV.delete(key) }
      example.run
    ensure
      old.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end

    it "writes a fragment with group summaries and verbose logging on a single shard" do
      Dir.mktmpdir do |root|
        library_directory = File.join(root, "lib")
        FileUtils.mkdir_p(library_directory)
        source_path = File.join(library_directory, "sample.rb")
        File.write(source_path, "SAMPLE = 1\n")
        output_path = File.join(root, "coverage", "frag.json")
        cfg = {
          root: root,
          output_path: output_path,
          track_under: ["lib"],
          track_files: ["lib/**/*.rb"],
          groups: {"Lib" => "lib/**/*.rb"},
          reject_patterns: [],
          minimum_line_percent: 0,
          strict: false,
          meta: {},
          fragment_meta: {},
          formatter: nil,
          shard_total_at_start: 1
        }
        ENV["POLYRUN_SHARD_TOTAL"] = "1"
        ENV["POLYRUN_COVERAGE_VERBOSE"] = "1"
        with_collector_config(cfg) do
          allow(Coverage).to receive(:result).and_return(
            {source_path => {lines: [1]}}
          )
          expect(Polyrun::Log).to receive(:warn).at_least(:once)
          Polyrun::Coverage::Collector.finish
        end
        payload = JSON.parse(File.read(output_path))
        expect(payload.fetch("groups")).to have_key("Lib")
      end
    end
  end
end
