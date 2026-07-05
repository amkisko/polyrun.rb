require "spec_helper"

RSpec.describe Polyrun::SpecQuality::MinitestHook do
  around do |ex|
    prev = ENV.to_h
    ENV["POLYRUN_SPEC_QUALITY"] = "1"
    Polyrun::SpecQuality.instance_variable_set(:@config, nil) if Polyrun::SpecQuality.instance_variable_defined?(:@config)
    ex.run
  ensure
    ENV.replace(prev)
    Polyrun::SpecQuality.instance_variable_set(:@config, nil) if Polyrun::SpecQuality.instance_variable_defined?(:@config)
  end

  it "install! prepends the hook module into Minitest::Test" do
    stub_minitest = Module.new do
      const_set(:Test, Class.new)
    end
    stub_const("Minitest", stub_minitest)

    Dir.mktmpdir do |dir|
      described_class.install!(only_if: -> { true }, root: dir, output_path: File.join(dir, "q.jsonl"))
      expect(Minitest::Test.ancestors).to include(Polyrun::SpecQuality::MinitestHook::SpecQualityTestHook)
    end
  end
end
