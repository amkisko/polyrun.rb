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

  it "ping! writes timestamp and optional location on second line" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "p.txt")
      ENV["POLYRUN_WORKER_PING_FILE"] = path
      described_class.ping!(location: "spec/a_spec.rb:12")
      raw = File.binread(path)
      time_line, loc_line = raw.split("\n", 2)
      expect(time_line.to_f).to be > 0
      expect(loc_line).to eq "spec/a_spec.rb:12"
    end
  end
end
