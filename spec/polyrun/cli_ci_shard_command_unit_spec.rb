require "spec_helper"
require "tmpdir"

RSpec.describe "Polyrun::CLI CiShardRunCommand helpers" do
  let(:cli) { Polyrun::CLI.new }

  describe "#ci_shard_parse_shard_processes!" do
    it "strips --shard-processes and --workers and leaves plan flags" do
      pc = {}
      argv = ["--shard-processes", "4", "--shard", "0", "--total", "3"]
      w, err = cli.send(:ci_shard_parse_shard_processes!, argv, pc)
      expect(err).to be_nil
      expect(w).to eq(4)
      expect(argv).to eq(["--shard", "0", "--total", "3"])
    end

    it "uses POLYRUN_SHARD_PROCESSES default from Resolver when flags absent" do
      pc = {"shard_processes" => 2}
      argv = ["--shard", "0"]
      w, err = cli.send(:ci_shard_parse_shard_processes!, argv, pc)
      expect(err).to be_nil
      expect(w).to eq(2)
      expect(argv).to eq(["--shard", "0"])
    end

    it "returns [nil, 2] when --shard-processes value is not an integer" do
      pc = {}
      argv = ["--shard-processes", "nope", "--shard", "0"]
      w, err = cli.send(:ci_shard_parse_shard_processes!, argv, pc)
      expect(w).to be_nil
      expect(err).to eq(2)
    end

    it "returns [nil, 2] when --shard-processes has no value" do
      pc = {}
      argv = ["--shard-processes"]
      w, err = cli.send(:ci_shard_parse_shard_processes!, argv, pc)
      expect(w).to be_nil
      expect(err).to eq(2)
    end
  end

  describe "#ci_shard_normalize_shard_processes" do
    it "returns exit code 2 when workers < 1" do
      _w, err = cli.send(:ci_shard_normalize_shard_processes, 0)
      expect(err).to eq(2)
    end

    it "caps at MAX_PARALLEL_WORKERS" do
      w, err = cli.send(:ci_shard_normalize_shard_processes, Polyrun::Config::MAX_PARALLEL_WORKERS + 5)
      expect(err).to be_nil
      expect(w).to eq(Polyrun::Config::MAX_PARALLEL_WORKERS)
    end
  end

  describe "#ci_shard_matrix_context" do
    it "returns nil when matrix has a single job" do
      pc = {"shard_total" => 1, "shard_index" => 0}
      mx, mt = cli.send(:ci_shard_matrix_context, pc, 4)
      expect(mx).to be_nil
      expect(mt).to be_nil
    end

    it "returns nil when only one local process" do
      pc = {"shard_total" => 4, "shard_index" => 1}
      mx, mt = cli.send(:ci_shard_matrix_context, pc, 1)
      expect(mx).to be_nil
      expect(mt).to be_nil
    end

    it "returns matrix index and total when N>1 and M>1" do
      pc = {"shard_total" => 3, "shard_index" => 2}
      mx, mt = cli.send(:ci_shard_matrix_context, pc, 2)
      expect(mx).to eq(2)
      expect(mt).to eq(3)
    end
  end
end
