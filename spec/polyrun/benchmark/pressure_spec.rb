# frozen_string_literal: true

require "spec_helper"
require "polyrun/benchmark/pressure"

RSpec.describe Polyrun::Benchmark::Pressure do
  it "measures wall, cpu, and allocation counters for a workload" do
    result = described_class.measure(label: "alloc", ops: 1_000) do
      1_000.times { +"x" * 64 }
    end

    expect(result["label"]).to eq("alloc")
    expect(result["metrics"]["wall_s"]).to be > 0
    expect(result["metrics"]["cpu_s"]).to be >= 0
    expect(result.dig("metrics", "gc", "allocated_objects")).to be > 0
    expect(result["report"]).to include("alloc")
  end

  it "builds stricter targets from a baseline" do
    metrics = {
      "wall_s" => 10.0,
      "cpu_s" => 8.0,
      "rss_delta_bytes" => 1_000_000,
      "heap_delta_bytes" => 500_000,
      "storage_delta_bytes" => 100,
      "network_in_bytes" => 200,
      "network_out_bytes" => 300
    }
    targets = described_class.targets_from(metrics, factor: 0.85)

    expect(targets["wall_s"]).to eq(8.5)
    expect(targets["cpu_s"]).to eq(6.8)
    expect(described_class.targets_met?(metrics, targets)).to eq(false)
    expect(described_class.targets_met?(
      metrics.merge("wall_s" => 8.0, "cpu_s" => 6.0, "rss_delta_bytes" => 100,
        "heap_delta_bytes" => 100, "storage_delta_bytes" => 10,
        "network_in_bytes" => 10, "network_out_bytes" => 10),
      targets
    )).to eq(true)
  end
end
