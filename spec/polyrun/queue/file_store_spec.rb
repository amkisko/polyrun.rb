require "spec_helper"
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
end
