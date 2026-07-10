require "spec_helper"
require "stringio"
require "tmpdir"

RSpec.describe Polyrun::WorkerOutput do
  def with_worker_output_env(*keys)
    old = keys.to_h { |key| [key, ENV[key]] }
    keys.each { |key| ENV.delete(key) }
    yield
  ensure
    described_class.shutdown_all!
    old.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  describe ".routing_enabled?" do
    around do |example|
      with_worker_output_env("POLYRUN_WORKER_OUTPUT_ROUTING", "POLYRUN_WORKER_LOG_DIR", &example)
    end

    it "is off by default" do
      expect(described_class.routing_enabled?).to be(false)
    end

    it "is on when POLYRUN_WORKER_OUTPUT_ROUTING=1" do
      ENV["POLYRUN_WORKER_OUTPUT_ROUTING"] = "1"
      expect(described_class.routing_enabled?).to be(true)
    end

    it "is on when POLYRUN_WORKER_LOG_DIR is set" do
      ENV["POLYRUN_WORKER_LOG_DIR"] = "tmp/custom-workers"
      expect(described_class.routing_enabled?).to be(true)
    end

    it "is off when POLYRUN_WORKER_OUTPUT_ROUTING=0 even with log dir" do
      ENV["POLYRUN_WORKER_OUTPUT_ROUTING"] = "0"
      ENV["POLYRUN_WORKER_LOG_DIR"] = "tmp/custom-workers"
      expect(described_class.routing_enabled?).to be(false)
    end
  end

  describe Polyrun::WorkerOutput::LineForwarder do
    it "prefixes newline-terminated lines and passes carriage-return progress chunks through" do
      log_io = StringIO.new
      tty_io = StringIO.new
      forwarder = described_class.new(shard: 2, pid: 99, log_io: log_io, prefix_live: true, tty_io: tty_io)

      forwarder.consume("hello\n")
      forwarder.consume("\rprogress")
      forwarder.flush

      expect(log_io.string).to include("shard=2 pid=99")
      expect(log_io.string).to include("hello\n")
      expect(log_io.string).to include("\rprogress")
      expect(tty_io.string).to include("hello\n")
      expect(tty_io.string).to include("\rprogress")
    end

    it "flushes a trailing partial line" do
      log_io = StringIO.new
      forwarder = described_class.new(shard: 0, pid: 1, log_io: log_io, prefix_live: false, tty_io: StringIO.new)
      forwarder.consume("tail")
      forwarder.flush
      expect(log_io.string).to include("tail")
    end
  end

  describe Polyrun::WorkerOutput::WorkerForwarder do
    it "writes stdout and stderr streams to the shard log" do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "shard-0.log")
        forwarder = described_class.new(shard: 0, pid: $$, log_path: path, prefix_live: false)
        forwarder.consume(:stdout, "stdout-line\n")
        forwarder.consume(:stderr, "stderr-line\n")
        forwarder.close
        body = File.read(path)
        expect(body).to include("stdout-line\n").and include("stderr-line\n")
      end
    end
  end

  describe ".prefix_live?, .log_path_for, and .warn_shard_log" do
    around do |example|
      with_worker_output_env(
        "POLYRUN_WORKER_OUTPUT_ROUTING",
        "POLYRUN_WORKER_LOG_DIR",
        "POLYRUN_WORKER_OUTPUT_PREFIX",
        &example
      )
    end

    it "defaults prefix echo on and resolves shard log paths" do
      expect(described_class.prefix_live?).to be(true)
      expect(described_class.log_path_for(2)).to end_with("tmp/polyrun/workers/shard-2.log")
      expect(described_class.worker_log_directory_label).to eq("tmp/polyrun/workers")
    end

    it "disables live prefix echo when POLYRUN_WORKER_OUTPUT_PREFIX=0" do
      ENV["POLYRUN_WORKER_OUTPUT_PREFIX"] = "0"
      expect(described_class.prefix_live?).to be(false)
    end

    it "warns with the shard log path when routing is enabled" do
      ENV["POLYRUN_WORKER_OUTPUT_ROUTING"] = "1"
      expect(Polyrun::Log).to receive(:warn).with(/shard 3 worker log/)
      described_class.warn_shard_log(3)
    end
  end

  describe ".spawn_worker, .finish_worker, and .shutdown_all!" do
    around do |example|
      with_worker_output_env(
        "POLYRUN_WORKER_OUTPUT_ROUTING",
        "POLYRUN_WORKER_LOG_DIR",
        "POLYRUN_WORKER_OUTPUT_PREFIX",
        &example
      )
    end

    it "captures child stdout and stderr in the shard log" do
      Dir.mktmpdir do |directory|
        ENV["POLYRUN_WORKER_OUTPUT_ROUTING"] = "1"
        ENV["POLYRUN_WORKER_LOG_DIR"] = directory
        ENV["POLYRUN_WORKER_OUTPUT_PREFIX"] = "0"
        hook_configuration = Polyrun::Hooks.new({})
        child_environment = {"POLYRUN_SHARD_INDEX" => "0"}
        pid = described_class.spawn_worker(child_environment, "echo", ["worker-marker"], hook_configuration)
        Process.wait(pid)
        described_class.finish_worker(pid)
        log_body = File.read(File.join(directory, "shard-0.log"))
        expect(log_body).to include("worker-marker")
      end
    end
  end

  describe ".prepare_log_dir!" do
    it "creates the directory and clears stale shard logs" do
      Dir.mktmpdir do |dir|
        old = ENV["POLYRUN_WORKER_LOG_DIR"]
        ENV["POLYRUN_WORKER_LOG_DIR"] = dir
        stale = File.join(dir, "shard-0.log")
        File.write(stale, "old")
        described_class.prepare_log_dir!
        expect(Dir.exist?(dir)).to be(true)
        expect(File.exist?(stale)).to be(false)
      ensure
        old.nil? ? ENV.delete("POLYRUN_WORKER_LOG_DIR") : ENV["POLYRUN_WORKER_LOG_DIR"] = old
      end
    end
  end
end
