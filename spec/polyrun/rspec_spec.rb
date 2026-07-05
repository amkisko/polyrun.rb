require "spec_helper"

RSpec.describe Polyrun::RSpec do
  it "install_example_timing! registers a formatter" do
    count_before = ::RSpec.configuration.formatters.count
    described_class.install_example_timing!
    expect(::RSpec.configuration.formatters.count).to be > count_before
  end

  it "install_worker_ping! registers lifecycle hooks" do
    expect { described_class.install_worker_ping! }.not_to raise_error
  end

  it "install_failure_fragments! is a no-op when env is unset" do
    ENV.delete("POLYRUN_FAILURE_FRAGMENTS")
    count_before = ::RSpec.configuration.formatters.count
    described_class.install_failure_fragments!
    expect(::RSpec.configuration.formatters.count).to eq(count_before)
  end

  it "install_failure_fragments! registers formatter when env is set" do
    ENV["POLYRUN_FAILURE_FRAGMENTS"] = "1"
    count_before = ::RSpec.configuration.formatters.count
    described_class.install_failure_fragments!
    expect(::RSpec.configuration.formatters.count).to be > count_before
  end

  it "install_parallel_provisioning! registers before suite hook" do
    expect { described_class.install_parallel_provisioning!(::RSpec.configuration) }.not_to raise_error
  end

  it "install_example_timing! accepts custom output_path" do
    out = Dir::Tmpname.create("timing") {}
    count_before = ::RSpec.configuration.formatters.count
    described_class.install_example_timing!(output_path: out)
    expect(::RSpec.configuration.formatters.count).to be > count_before
  end

  it "install_spec_quality! installs hook when enabled" do
    ENV["POLYRUN_SPEC_QUALITY"] = "1"
    described_class.install_spec_quality!(only_if: -> { true }, root: Dir.mktmpdir)
    expect(defined?(Polyrun::SpecQuality::RspecHook)).to be_truthy
  end
end
