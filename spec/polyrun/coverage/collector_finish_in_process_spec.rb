require "spec_helper"
require "tmpdir"

RSpec.describe "Polyrun::Coverage::Collector.finish (in-process)" do
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
