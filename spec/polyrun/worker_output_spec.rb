require "spec_helper"
require "stringio"
require "tmpdir"

RSpec.describe Polyrun::WorkerOutput do
  describe ".routing_enabled?" do
    around do |example|
      keys = %w[POLYRUN_WORKER_OUTPUT_ROUTING POLYRUN_WORKER_LOG_DIR]
      old = keys.to_h { |key| [key, ENV[key]] }
      keys.each { |key| ENV.delete(key) }
      example.run
    ensure
      old.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
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
