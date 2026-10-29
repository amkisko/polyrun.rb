require "spec_helper"
require "fileutils"
require "json"
require "tmpdir"

RSpec.describe Polyrun::Queue::FileStore do
  it "recovers a claim intent by returning paths to pending" do
    Dir.mktmpdir do |dir|
      s = described_class.new(dir)
      s.init!(%w[a b])
      File.write(
        File.join(dir, "intent.json"),
        JSON.generate("op" => "claim", "lease_id" => "dead-lease", "worker_id" => "w1", "paths" => %w[a])
      )
      # Simulate pending already drained for path a (crash after take, before lease write).
      meta = JSON.parse(File.read(File.join(dir, "queue.json")))
      meta["pending_count"] = 1
      File.write(File.join(dir, "queue.json"), JSON.generate(meta))
      File.write(File.join(dir, "pending", "000001.json"), JSON.generate(%w[b]))
      st = s.status
      expect(st["pending"]).to eq(2)
      expect(File).not_to exist(File.join(dir, "intent.json"))
    end
  end

  it "quarantines paths after POLYRUN_QUEUE_MAX_ATTEMPTS reclaims" do
    old = ENV["POLYRUN_QUEUE_MAX_ATTEMPTS"]
    ENV["POLYRUN_QUEUE_MAX_ATTEMPTS"] = "2"
    Dir.mktmpdir do |dir|
      s = described_class.new(dir)
      s.init!(%w[poison.rb])
      2.times do
        r = s.claim!(worker_id: "w1", batch_size: 1)
        s.reclaim_lease!(r["lease_id"])
      end
      expect(s.status["pending"]).to eq(0)
      expect(s.status["leases"]).to eq(0)
      failed = File.readlines(File.join(dir, "failed.jsonl")).map { |line| JSON.parse(line) }
      expect(failed.size).to eq(1)
      expect(failed.first["path"]).to eq("poison.rb")
    end
  ensure
    old.nil? ? ENV.delete("POLYRUN_QUEUE_MAX_ATTEMPTS") : ENV["POLYRUN_QUEUE_MAX_ATTEMPTS"] = old
  end
end
