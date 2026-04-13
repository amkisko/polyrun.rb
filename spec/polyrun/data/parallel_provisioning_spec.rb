require "spec_helper"

RSpec.describe Polyrun::Data::ParallelProvisioning do
  around do |example|
    saved = %w[POLYRUN_SHARD_TOTAL POLYRUN_SHARD_INDEX TEST_ENV_NUMBER].to_h { |k| [k, ENV[k]] }
    example.run
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  before { described_class.reset_configuration! }

  it "detects parallel_workers? from POLYRUN_SHARD_TOTAL" do
    ENV["POLYRUN_SHARD_TOTAL"] = "4"
    expect(described_class.parallel_workers?).to be true
    ENV["POLYRUN_SHARD_TOTAL"] = "1"
    expect(described_class.parallel_workers?).to be false
  end

  it "reads shard_index from POLYRUN_SHARD_INDEX or TEST_ENV_NUMBER" do
    ENV["POLYRUN_SHARD_TOTAL"] = "3"
    ENV["POLYRUN_SHARD_INDEX"] = "2"
    expect(described_class.shard_index).to eq(2)

    ENV.delete("POLYRUN_SHARD_INDEX")
    ENV["TEST_ENV_NUMBER"] = "1"
    expect(described_class.shard_index).to eq(0)
    ENV["TEST_ENV_NUMBER"] = "3"
    expect(described_class.shard_index).to eq(2)
  end

  it "runs parallel_worker_hook when parallel" do
    log = []
    described_class.configure do |c|
      c.serial { log << :serial }
      c.parallel_worker { log << :parallel }
    end
    ENV["POLYRUN_SHARD_TOTAL"] = "2"
    described_class.run_suite_hooks!
    expect(log).to eq([:parallel])
  end

  it "runs serial_hook when single shard" do
    log = []
    described_class.configure do |c|
      c.serial { log << :serial }
      c.parallel_worker { log << :parallel }
    end
    ENV["POLYRUN_SHARD_TOTAL"] = "1"
    described_class.run_suite_hooks!
    expect(log).to eq([:serial])
  end
end
