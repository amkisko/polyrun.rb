require "spec_helper"
require "polyrun/spec_quality/profile"

RSpec.describe Polyrun::SpecQuality::Profile do
  it "snapshot returns cpu and gc fields" do
    snap = described_class.snapshot
    expect(snap).to include("cpu_user", "cpu_system", "gc_allocated")
  end

  it "snapshot skips gc fields when mem is not requested" do
    snap = described_class.snapshot(dimensions: %w[cpu])
    expect(snap).to include("cpu_user", "cpu_system")
    expect(snap).not_to include("gc_allocated", "gc_heap_live")
  end

  it "snapshot skips io fields when io is not requested" do
    snap = described_class.snapshot(dimensions: %w[cpu mem])
    expect(snap).not_to include("io_read_bytes", "io_write_bytes")
  end

  it "diff subtracts numeric fields" do
    before = {"cpu_user" => 1.0, "gc_allocated" => 100}
    after = {"cpu_user" => 1.5, "gc_allocated" => 250}
    delta = described_class.diff(before, after)
    expect(delta["cpu_user"]).to eq(0.5)
    expect(delta["gc_allocated"]).to eq(150)
  end

  it "slice_profile keeps only requested dimensions" do
    diff = {"wall" => 1.2, "cpu_user" => 0.1, "gc_allocated" => 50, "io_read_bytes" => 10}
    sliced = described_class.slice_profile(diff, %w[wall cpu mem])
    expect(sliced.keys).to contain_exactly("wall", "cpu_user", "gc_allocated")
  end

  it "slice_profile returns full diff when dimensions are empty" do
    diff = {"wall" => 1.0}
    expect(described_class.slice_profile(diff, [])).to eq(diff)
  end

  it "read_proc_io returns nil bytes when /proc is unavailable" do
    allow(File).to receive(:readable?).with("/proc/self/io").and_return(false)
    expect(described_class.read_proc_io).to eq(read_bytes: nil, write_bytes: nil)
  end
end
