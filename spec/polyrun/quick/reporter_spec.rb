require "spec_helper"
require "polyrun/quick/reporter"
require "stringio"

RSpec.describe Polyrun::Quick::Reporter do
  it "lists slowest examples at or above the threshold" do
    out = StringIO.new
    err = StringIO.new
    reporter = described_class.new(out, err, false)
    reporter.pass("g", "fast", duration_seconds: 0.001)
    reporter.pass("g", "slow", duration_seconds: 0.2)
    expect(reporter.summary).to eq(0)
    expect(out.string).to include("Slowest:")
    expect(out.string).to include("slow")
    expect(out.string).not_to include("fast")
  end
end
