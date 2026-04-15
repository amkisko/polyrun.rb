require "spec_helper"

RSpec.describe "Polyrun::CLI#shard_child_env" do
  let(:cli) { Polyrun::CLI.new }
  let(:cfg) { Polyrun::Config.load(path: nil) }

  it "sets POLYRUN_SHARD_MATRIX_INDEX and POLYRUN_SHARD_MATRIX_TOTAL when matrix_total > 1" do
    env = cli.send(:shard_child_env, cfg: cfg, workers: 3, shard: 1, matrix_index: 2, matrix_total: 5)
    expect(env["POLYRUN_SHARD_INDEX"]).to eq("1")
    expect(env["POLYRUN_SHARD_TOTAL"]).to eq("3")
    expect(env["POLYRUN_SHARD_MATRIX_INDEX"]).to eq("2")
    expect(env["POLYRUN_SHARD_MATRIX_TOTAL"]).to eq("5")
  end

  it "does not set matrix keys when matrix_total is nil" do
    env = cli.send(:shard_child_env, cfg: cfg, workers: 3, shard: 1, matrix_index: nil, matrix_total: nil)
    expect(env["POLYRUN_SHARD_INDEX"]).to eq("1")
    expect(env).not_to have_key("POLYRUN_SHARD_MATRIX_INDEX")
    expect(env).not_to have_key("POLYRUN_SHARD_MATRIX_TOTAL")
  end

  it "does not set matrix keys when matrix_total is 1" do
    env = cli.send(:shard_child_env, cfg: cfg, workers: 3, shard: 1, matrix_index: 0, matrix_total: 1)
    expect(env).not_to have_key("POLYRUN_SHARD_MATRIX_INDEX")
  end

  it "does not set matrix keys when matrix_total > 1 but matrix_index is nil" do
    env = cli.send(:shard_child_env, cfg: cfg, workers: 3, shard: 1, matrix_index: nil, matrix_total: 3)
    expect(env).not_to have_key("POLYRUN_SHARD_MATRIX_INDEX")
    expect(env).not_to have_key("POLYRUN_SHARD_MATRIX_TOTAL")
  end
end
