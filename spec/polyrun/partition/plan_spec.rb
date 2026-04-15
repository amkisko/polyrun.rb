require "spec_helper"

RSpec.describe Polyrun::Partition::Plan do
  it "round-robin assigns stable sorted order" do
    plan = described_class.new(items: %w[c a b], total_shards: 2, strategy: "round_robin")
    expect(plan.shard(0)).to eq(%w[a c])
    expect(plan.shard(1)).to eq(%w[b])
  end

  it "random_round_robin is deterministic with seed (Fisher-Yates)" do
    a = described_class.new(items: (1..6).map(&:to_s), total_shards: 2, strategy: "random_round_robin", seed: 42)
    b = described_class.new(items: (1..6).map(&:to_s), total_shards: 2, strategy: "random_round_robin", seed: 42)
    expect(a.shard(0)).to eq(%w[1 6 5])
    expect(a.shard(1)).to eq(%w[2 3 4])
    expect(a.shard(0)).to eq(b.shard(0))
    expect(a.shard(1)).to eq(b.shard(1))
  end

  it "raises on invalid shard index" do
    plan = described_class.new(items: %w[a], total_shards: 1, strategy: "round_robin")
    expect { plan.shard(1) }.to raise_error(Polyrun::Error)
  end

  it "raises on unknown strategy" do
    plan = described_class.new(items: %w[a], total_shards: 1, strategy: "nope")
    expect { plan.ordered_items }.to raise_error(Polyrun::Error, /unknown partition strategy/)
  end

  it "manifest includes metadata" do
    plan = described_class.new(items: %w[x y], total_shards: 2, strategy: "round_robin")
    m = plan.manifest(0)
    expect(m["shard_total"]).to eq(2)
    expect(m["paths"]).to eq(["x"])
  end

  it "memoizes ordered_items across shard calls" do
    plan = described_class.new(items: %w[c b a], total_shards: 2, strategy: "round_robin")
    id1 = plan.ordered_items.object_id
    id2 = plan.ordered_items.object_id
    expect(id1).to eq(id2)
    plan.shard(0)
    plan.shard(1)
    expect(plan.ordered_items.object_id).to eq(id1)
  end

  it "round_robin partitions ordered_items across shards without overlap or gaps (mod_shards)" do
    items = (1..100).map { |i| format("p_%03d", i) }
    workers = 7
    plan = described_class.new(items: items, total_shards: workers, strategy: "round_robin")
    ordered = plan.ordered_items
    expect(ordered).to eq(items.sort)
    partitioned = workers.times.flat_map { |j| plan.shard(j) }
    expect(partitioned.size).to eq(ordered.size)
    expect(partitioned.tally).to eq(ordered.tally)
  end

  it "random_round_robin partitions ordered_items across shards without overlap or gaps" do
    items = (1..50).map { |i| format("p_%03d", i) }
    workers = 5
    plan = described_class.new(items: items, total_shards: workers, strategy: "random_round_robin", seed: 42)
    ordered = plan.ordered_items
    partitioned = workers.times.flat_map { |j| plan.shard(j) }
    expect(partitioned.size).to eq(ordered.size)
    expect(partitioned.tally).to eq(ordered.tally)
  end

  it "cost_binpack balances heavy file across shards (LPT greedy)" do
    costs = {"a" => 10.0, "b" => 5.0, "c" => 5.0}
    plan = described_class.new(
      items: %w[a b c],
      total_shards: 2,
      strategy: "cost_binpack",
      costs: costs
    )
    expect(plan.shard(0)).to eq(%w[a])
    expect(plan.shard(1)).to contain_exactly("b", "c")
    expect(plan.shard_weight_totals.sum).to be_within(0.001).of(20.0)
  end

  it "manifest includes shard_seconds for cost strategies" do
    plan = described_class.new(
      items: %w[x y],
      total_shards: 2,
      strategy: "binpack",
      costs: {"x" => 3.0, "y" => 1.0}
    )
    m = plan.manifest(0)
    expect(m["shard_seconds"]).to eq([3.0, 1.0])
  end

  it "raises when cost strategy is used without costs" do
    expect do
      described_class.new(items: %w[a], total_shards: 1, strategy: "cost_binpack", costs: nil)
    end.to raise_error(Polyrun::Error, /timing map/)
  end

  it "hrw assigns deterministically per path" do
    salt = "polyrun-hrw"
    a = Polyrun::Partition::Hrw.shard_for(path: "spec/a_spec.rb", total_shards: 3, seed: salt)
    b = Polyrun::Partition::Hrw.shard_for(path: "spec/a_spec.rb", total_shards: 3, seed: salt)
    expect(a).to eq(b)
    plan = described_class.new(items: %w[spec/a_spec.rb spec/b_spec.rb], total_shards: 3, strategy: "hrw", seed: nil)
    expect(plan.shard(a)).to include("spec/a_spec.rb")
  end

  it "cost_binpack uses per-example weights when timing_granularity is example (experimental)" do
    Dir.mktmpdir do |dir|
      a = "a_spec.rb:1"
      b = "b_spec.rb:2"
      c = "c_spec.rb:3"
      costs = {
        "#{File.expand_path("a_spec.rb", dir)}:1" => 10.0,
        "#{File.expand_path("b_spec.rb", dir)}:2" => 5.0,
        "#{File.expand_path("c_spec.rb", dir)}:3" => 5.0
      }
      root = File.expand_path(dir)
      plan = described_class.new(
        items: [a, b, c],
        total_shards: 2,
        strategy: "cost_binpack",
        costs: costs,
        root: dir,
        timing_granularity: :example
      )
      exp = lambda { |rel, line| Polyrun::Partition::TimingKeys.normalize_locator("#{rel}:#{line}", root, :example) }
      expect(plan.shard(0)).to eq([exp.call("a_spec.rb", 1)])
      expect(plan.shard(1)).to contain_exactly(exp.call("b_spec.rb", 2), exp.call("c_spec.rb", 3))
      m = plan.manifest(0)
      expect(m["timing_granularity"]).to eq("example")
    end
  end

  it "pins override LPT placement" do
    c = Polyrun::Partition::Constraints.new(
      pin_map: {"b" => 1},
      root: Dir.pwd
    )
    costs = {"a" => 100.0, "b" => 1.0, "c" => 1.0}
    plan = described_class.new(
      items: %w[a b c],
      total_shards: 2,
      strategy: "cost_binpack",
      costs: costs,
      constraints: c,
      root: Dir.pwd
    )
    expect(plan.shard(1)).to include("b")
  end
end
