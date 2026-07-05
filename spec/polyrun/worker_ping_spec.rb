require "polyrun/worker_ping"

RSpec.describe Polyrun::WorkerPing do
  around do |example|
    ENV.delete("POLYRUN_WORKER_PING_FILE")
    example.run
    ENV.delete("POLYRUN_WORKER_PING_FILE")
  end

  it "ping! no-ops when POLYRUN_WORKER_PING_FILE is unset" do
    expect { described_class.ping! }.not_to raise_error
  end

  it "ping! writes only timestamp when location omitted" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "p.txt")
      ENV["POLYRUN_WORKER_PING_FILE"] = path
      described_class.ping!
      raw = File.binread(path)
      expect(raw).not_to include("\n")
      expect(raw.to_f).to be > 0
    end
  end

  it "ensure_interval_ping_thread! completes when POLYRUN_WORKER_PING_THREAD is unset" do
    expect { described_class.ensure_interval_ping_thread! }.not_to raise_error
  end

  it "ensure_interval_ping_thread! starts periodic ping when thread env is set" do
    described_class.instance_variable_set(:@interval_ping_started, nil)
    described_class.instance_variable_set(:@interval_ping_mx, nil)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "p.txt")
      ENV["POLYRUN_WORKER_PING_FILE"] = path
      ENV["POLYRUN_WORKER_PING_THREAD"] = "1"
      ENV["POLYRUN_WORKER_PING_INTERVAL_SEC"] = "0.01"
      described_class.ensure_interval_ping_thread!
      sleep 0.05
      expect(File.binread(path)).not_to be_empty
    end
  end
end
