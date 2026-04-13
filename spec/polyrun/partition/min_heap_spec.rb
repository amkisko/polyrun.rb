require "spec_helper"

RSpec.describe Polyrun::Partition::MinHeap do
  it "pops increasing load with tie-break on shard index" do
    h = described_class.new
    h.push(0.0, 2)
    h.push(0.0, 0)
    h.push(0.0, 1)
    load, j = h.pop_min
    expect([load, j]).to eq([0.0, 0])
  end
end
