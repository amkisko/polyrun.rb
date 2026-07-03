require "spec_helper"
require "fileutils"
require "json"
require "tmpdir"

RSpec.describe Polyrun::Queue::FileStore do
  it "init, claim, ack, status" do
    Dir.mktmpdir do |dir|
      s = described_class.new(dir)
      s.init!(%w[a b c d])
      st = s.status
      expect(st["pending"]).to eq(4)
      r = s.claim!(worker_id: "w1", batch_size: 2)
      expect(r["paths"].size).to eq(2)
      st = s.status
      expect(st["pending"]).to eq(2)
      s.ack!(lease_id: r["lease_id"], worker_id: "w1")
      st = s.status
      expect(st["done"]).to eq(2)
    end
  end

  it "returns empty paths when pending is empty" do
    Dir.mktmpdir do |dir|
      s = described_class.new(dir)
      s.init!(%w[a])
      s.claim!(worker_id: "w1", batch_size: 5)
      r = s.claim!(worker_id: "w2", batch_size: 5)
      expect(r["paths"]).to eq([])
    end
  end

  it "raises on ack with unknown lease id" do
    Dir.mktmpdir do |dir|
      s = described_class.new(dir)
      s.init!(%w[a])
      expect do
        s.ack!(lease_id: "00000000-0000-4000-8000-000000000000", worker_id: "w1")
      end.to raise_error(Polyrun::Error, /unknown lease/)
    end
  end

  it "raises on ack when worker id does not match lease" do
    Dir.mktmpdir do |dir|
      s = described_class.new(dir)
      s.init!(%w[a b])
      r = s.claim!(worker_id: "w1", batch_size: 1)
      expect do
        s.ack!(lease_id: r["lease_id"], worker_id: "w2")
      end.to raise_error(Polyrun::Error, /lease worker mismatch/)
    end
  end

  it "raises when pending_count and pending chunks disagree" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "pending"))
      File.write(File.join(dir, "queue.json"), JSON.generate(
        "created_at" => Time.now.utc.iso8601,
        "pending_count" => 2,
        "done_count" => 0,
        "chunk_size" => 500
      ))
      s = described_class.new(dir)
      expect do
        s.claim!(worker_id: "w1", batch_size: 1)
      end.to raise_error(Polyrun::Error, /queue corrupt/)
    end
  end

  it "claim reads only head chunk files (small CHUNK_SIZE)" do
    stub_const("Polyrun::Queue::FileStore::CHUNK_SIZE", 2)
    Dir.mktmpdir do |dir|
      s = described_class.new(dir)
      s.init!(%w[a b c d e])
      r = s.claim!(worker_id: "w1", batch_size: 3)
      expect(r["paths"]).to eq(%w[a b c])
      st = s.status
      expect(st["pending"]).to eq(2)
    end
  end

  it "reclaim returns paths to pending" do
    Dir.mktmpdir do |dir|
      s = described_class.new(dir)
      s.init!(%w[a b c])
      s.claim!(worker_id: "w1", batch_size: 2)
      n = s.reclaim!(worker_id: "w1")
      expect(n).to eq(2)
      st = s.status
      expect(st["pending"]).to eq(3)
      expect(st["leases"]).to eq(0)
    end
  end

  it "reclaim_lease! returns paths to pending and removes the lease" do
    Dir.mktmpdir do |dir|
      s = described_class.new(dir)
      s.init!(%w[a b])
      r = s.claim!(worker_id: "w1", batch_size: 1)
      expect(s.reclaim_lease!(r["lease_id"])).to eq(1)
      st = s.status
      expect(st["pending"]).to eq(2)
      expect(st["leases"]).to eq(0)
    end
  end

  it "reclaim with older_than only reclaims stale leases across workers" do
    Dir.mktmpdir do |dir|
      s = described_class.new(dir)
      s.init!(%w[a b c d])
      fresh = s.claim!(worker_id: "w1", batch_size: 1)
      stale_lease_id = fresh["lease_id"]
      leases_path = File.join(dir, "leases.json")
      leases = JSON.parse(File.read(leases_path))
      leases[stale_lease_id]["claimed_at"] = (Time.now.utc - 3600).iso8601
      File.write(leases_path, JSON.generate(leases))

      s.claim!(worker_id: "w2", batch_size: 1)

      n = s.reclaim!(older_than: 600)
      expect(n).to eq(1)
      st = s.status(detailed: true)
      expect(st["leases"]).to eq(1)
      expect(st["pending"]).to eq(3)
    end
  end

  it "reclaim with worker and older-than only reclaims stale leases for that worker" do
    Dir.mktmpdir do |dir|
      s = described_class.new(dir)
      s.init!(%w[a b c d])
      fresh = s.claim!(worker_id: "w1", batch_size: 1)
      stale_lease_id = fresh["lease_id"]
      leases_path = File.join(dir, "leases.json")
      leases = JSON.parse(File.read(leases_path))
      leases[stale_lease_id]["claimed_at"] = (Time.now.utc - 3600).iso8601
      File.write(leases_path, JSON.generate(leases))

      s.claim!(worker_id: "w1", batch_size: 1)

      n = s.reclaim!(worker_id: "w1", older_than: 600)
      expect(n).to eq(1)
      st = s.status(detailed: true)
      expect(st["leases"]).to eq(1)
      expect(st["lease_details"].first["worker_id"]).to eq("w1")
      expect(st["pending"]).to eq(3)
    end
  end

  it "status detailed includes lease_details" do
    Dir.mktmpdir do |dir|
      s = described_class.new(dir)
      s.init!(%w[a])
      s.claim!(worker_id: "w1", batch_size: 1)
      st = s.status(detailed: true)
      expect(st["lease_details"].size).to eq(1)
      expect(st["lease_details"].first["worker_id"]).to eq("w1")
    end
  end
end
