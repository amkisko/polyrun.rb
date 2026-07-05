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

  it "install! registers example hooks when predicate passes" do
    Dir.mktmpdir do |dir|
      described_class.install!(only_if: -> { true }, root: dir, output_path: File.join(dir, "q.jsonl"))
      expect(Polyrun::SpecQuality).to be_started
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
