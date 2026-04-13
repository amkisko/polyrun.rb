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
end
