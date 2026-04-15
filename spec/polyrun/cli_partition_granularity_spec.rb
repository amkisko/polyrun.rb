require "spec_helper"

RSpec.describe "CLI resolve_partition_timing_granularity" do
  let(:cli) { Polyrun::CLI.new }

  it "defaults to file" do
    expect(cli.send(:resolve_partition_timing_granularity, {}, nil)).to eq(:file)
  end

  it "reads POLYRUN_TIMING_GRANULARITY when config and CLI omit" do
    ENV["POLYRUN_TIMING_GRANULARITY"] = "example"
    begin
      expect(cli.send(:resolve_partition_timing_granularity, {}, nil)).to eq(:example)
    ensure
      ENV.delete("POLYRUN_TIMING_GRANULARITY")
    end
  end

  it "uses partition.timing_granularity from YAML when CLI is nil" do
    expect(cli.send(:resolve_partition_timing_granularity, {"timing_granularity" => "example"}, nil)).to eq(:example)
  end

  it "prefers explicit CLI value over YAML partition" do
    expect(cli.send(:resolve_partition_timing_granularity, {"timing_granularity" => "example"}, "file")).to eq(:file)
  end

  it "prefers explicit CLI value over POLYRUN_TIMING_GRANULARITY" do
    ENV["POLYRUN_TIMING_GRANULARITY"] = "example"
    begin
      expect(cli.send(:resolve_partition_timing_granularity, {}, "file")).to eq(:file)
    ensure
      ENV.delete("POLYRUN_TIMING_GRANULARITY")
    end
  end
end
