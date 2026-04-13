require "spec_helper"

RSpec.describe Polyrun::Debug do
  around do |example|
    old_d = ENV.delete("DEBUG")
    old_p = ENV.delete("POLYRUN_DEBUG")
    example.run
    ENV["DEBUG"] = old_d
    ENV["POLYRUN_DEBUG"] = old_p
  end

  it "is enabled when DEBUG=1" do
    ENV["DEBUG"] = "1"
    expect(described_class.enabled?).to be true
  end

  it "is enabled when POLYRUN_DEBUG=true" do
    ENV["POLYRUN_DEBUG"] = "true"
    expect(described_class.enabled?).to be true
  end

  it "is disabled when unset" do
    expect(described_class.enabled?).to be false
  end

  it "time yields and returns value when disabled" do
    r = described_class.time("x") { 42 }
    expect(r).to eq(42)
  end

  it "time re-raises when disabled and block raises (rescue does not assume t0)" do
    expect do
      described_class.time("x") { raise "boom" }
    end.to raise_error(RuntimeError, "boom")
  end

  it "time logs to stderr when enabled" do
    ENV["DEBUG"] = "1"
    expect do
      described_class.time("label") { 7 }
    end.to output(/label.*start|label.*done/m).to_stderr
  end
end
