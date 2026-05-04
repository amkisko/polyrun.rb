require "spec_helper"
require "stringio"

RSpec.describe Polyrun::Log do
  after do
    described_class.reset_io!
  end

  it "routes warn to stderr by default" do
    io = StringIO.new
    described_class.stderr = io
    described_class.warn "hello"
    expect(io.string).to eq("hello\n")
  end

  it "routes puts to stdout by default" do
    io = StringIO.new
    described_class.stdout = io
    described_class.puts "hi"
    expect(io.string).to eq("hi\n")
  end

  it "print writes without extra newline" do
    io = StringIO.new
    described_class.stdout = io
    described_class.print "x"
    expect(io.string).to eq("x")
  end

  it "orchestration_warn mirrors to process stderr when POLYRUN_ORCHESTRATION_STDERR=1 and stderr sink is custom" do
    log_sink = StringIO.new
    described_class.stderr = log_sink
    ENV["POLYRUN_ORCHESTRATION_STDERR"] = "1"
    begin
      expect do
        described_class.orchestration_warn("timeout shard=0")
      end.to output("timeout shard=0\n").to_stderr

      expect(log_sink.string).to include("timeout shard=0")
    ensure
      ENV.delete("POLYRUN_ORCHESTRATION_STDERR")
    end
  end

  it "orchestration_warn does not duplicate when stderr follows process $stderr" do
    described_class.reset_io!
    ENV["POLYRUN_ORCHESTRATION_STDERR"] = "1"
    begin
      expect do
        described_class.orchestration_warn("once")
      end.to output("once\n").to_stderr
    ensure
      ENV.delete("POLYRUN_ORCHESTRATION_STDERR")
    end
  end
end
