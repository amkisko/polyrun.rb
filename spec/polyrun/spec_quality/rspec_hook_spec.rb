require "spec_helper"
require "polyrun/spec_quality/rspec_hook"

RSpec.describe Polyrun::SpecQuality::RspecHook do
  before do
    Polyrun::SpecQuality.instance_variable_set(:@config, nil) if Polyrun::SpecQuality.instance_variable_defined?(:@config)
    Polyrun::SpecQuality.instance_variable_set(:@current, nil) if Polyrun::SpecQuality.instance_variable_defined?(:@current)
  end

  around do |ex|
    prev = ENV.to_h
    ENV.delete("POLYRUN_SPEC_QUALITY_DISABLE")
    Polyrun::SpecQuality.instance_variable_set(:@config, nil) if Polyrun::SpecQuality.instance_variable_defined?(:@config)
    ex.run
  ensure
    ENV.replace(prev)
    Polyrun::SpecQuality.instance_variable_set(:@config, nil) if Polyrun::SpecQuality.instance_variable_defined?(:@config)
  end

  it "records examples through installed hooks in an isolated runner" do
    Dir.mktmpdir do |dir|
      probe = File.join(dir, "probe_spec.rb")
      output = File.join(dir, "q.jsonl")
      File.write(probe, 'RSpec.describe("probe") { it("runs") { raise unless 1 + 1 == 2 } }')
      source = <<~RUBY
        require "polyrun/spec_quality"
        require "polyrun/rspec_support"
        require "rspec/core"
        Polyrun::RSpecSupport.install_spec_quality!(only_if: -> { true }, root: ARGV[0], output_path: ARGV[1])
        exit RSpec::Core::Runner.run([ARGV[2]])
      RUBY
      log, status = Open3.capture2e({"POLYRUN_COVERAGE_DISABLE" => "1"}, Gem.ruby, "-I", File.expand_path("../../../lib", __dir__), "-e", source, dir, output, probe)
      expect(status.exitstatus).to eq(0), log
      rows = File.readlines(output).map { |line| JSON.parse(line) }
      expect(rows.size).to eq(1)
      expect(rows.first["example"]).to include("probe_spec.rb")
    end
  end

  it "install! is a no-op when predicate is false" do
    described_class.install!(only_if: -> { false })
    expect(Polyrun::SpecQuality).not_to be_started
  end

  it "infer_root falls back to cwd" do
    expect(described_class.infer_root).to eq(Dir.pwd)
  end
end
