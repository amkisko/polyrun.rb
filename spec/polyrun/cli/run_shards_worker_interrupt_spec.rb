require "spec_helper"

RSpec.describe Polyrun::CLI::RunShardsWorkerInterrupt do
  let(:handler) do
    Class.new do
      include Polyrun::CLI::RunShardsWorkerInterrupt
    end.new
  end

  describe "#run_shards_log_interrupt_workers" do
    around do |example|
      with_worker_output_env("POLYRUN_WORKER_OUTPUT_ROUTING", "POLYRUN_WORKER_LOG_DIR", &example)
    end

    it "mentions per-shard worker logs when routing is enabled" do
      ENV["POLYRUN_WORKER_OUTPUT_ROUTING"] = "1"
      expect(Polyrun::Log).to receive(:orchestration_warn).with(/SIGINT\/SIGTERM/)
      expect(Polyrun::Log).to receive(:warn).with(/per-shard worker logs/)
      handler.send(:run_shards_log_interrupt_workers, [{shard: 1, pid: 42}], nil)
    end

    it "mentions searching the orchestration log when routing is disabled" do
      expect(Polyrun::Log).to receive(:orchestration_warn).with(/SIGINT\/SIGTERM/)
      expect(Polyrun::Log).to receive(:warn).with(/search this log/)
      handler.send(:run_shards_log_interrupt_workers, [{shard: 0, pid: 9}], nil)
    end
  end

  describe "#run_shards_signal_workers_term and #run_shards_signal_workers_kill" do
    it "sends signals and ignores missing processes" do
      pid = spawn(RbConfig.ruby, "-e", "Signal.trap(:TERM) { exit 0 }; sleep 30")
      handler.send(:run_shards_signal_workers_term, [{shard: 0, pid: pid}])
      status = Process.wait(pid)
      expect(status).to eq(pid)
      expect { handler.send(:run_shards_signal_workers_kill, [{shard: 0, pid: 999_999}]) }.not_to raise_error
    end
  end

  describe "#run_shards_reap_worker_pids_interruptible" do
    it "reaps exited children and tolerates ECHILD" do
      pid = spawn(RbConfig.ruby, "-e", "exit 0")
      handler.send(:run_shards_reap_worker_pids_interruptible, [pid])
      expect { handler.send(:run_shards_reap_worker_pids_interruptible, [pid]) }.not_to raise_error
    end
  end

  describe "#run_shards_terminate_children!" do
    it "terminates and reaps worker processes" do
      pid = spawn(RbConfig.ruby, "-e", "Signal.trap(:TERM) { exit 0 }; sleep 30")
      expect { handler.send(:run_shards_terminate_children!, [{shard: 0, pid: pid}]) }.not_to raise_error
      expect { Process.kill(0, pid) }.to raise_error(Errno::ESRCH)
    end
  end

  describe "#run_shards_shutdown_on_signal!" do
    it "logs, shuts down worker output, and exits with the requested code" do
      expect(handler).to receive(:run_shards_log_interrupt_workers)
      expect(Polyrun::WorkerOutput).to receive(:shutdown_all!)
      expect(handler).to receive(:run_shards_terminate_children!)
      allow(Kernel).to receive(:exit).with(130) { raise SystemExit, 130 }
      expect { handler.send(:run_shards_shutdown_on_signal!, [], 130) }.to raise_error(SystemExit)
    end
  end

  def with_worker_output_env(*keys)
    old = keys.to_h { |key| [key, ENV[key]] }
    keys.each { |key| ENV.delete(key) }
    yield
  ensure
    Polyrun::WorkerOutput.shutdown_all!
    old.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
