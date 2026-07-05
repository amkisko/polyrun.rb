require "spec_helper"
require "polyrun/queue/worker_loop"
require "polyrun/queue/file_store"

RSpec.describe Polyrun::Queue::WorkerLoop do
  describe ".run" do
    it "acks successful batches until the queue is empty" do
      Dir.mktmpdir do |dir|
        store = Polyrun::Queue::FileStore.new(dir)
        store.init!(%w[a.rb b.rb c.rb])
        result = described_class.run(
          store: store,
          worker_id: "w1",
          batch: 2,
          cmd: [RbConfig.ruby, "-e", "exit 0"],
          on_failure: "exit"
        )
        expect(result).to eq(ok: 2, fail: 0, exit_code: 0)
        expect(store.status["pending"]).to eq(0)
        expect(store.status["done"]).to eq(3)
      end
    end

    it "returns non-zero exit code when a batch fails with on_failure exit" do
      Dir.mktmpdir do |dir|
        store = Polyrun::Queue::FileStore.new(dir)
        store.init!(%w[ok.rb fail.rb])
        script = 'exit(ARGV.any? { |p| File.basename(p).include?("fail") } ? 1 : 0)'
        result = described_class.run(
          store: store,
          worker_id: "w1",
          batch: 1,
          cmd: [RbConfig.ruby, "-e", script],
          on_failure: "exit"
        )
        expect(result[:exit_code]).to eq(1)
        expect(result[:fail]).to eq(1)
        expect(store.status["done"]).to eq(1)
        expect(store.status["leases"]).to eq(1)
      end
    end

    it "reclaims the lease and stops when on_failure is requeue" do
      Dir.mktmpdir do |dir|
        store = Polyrun::Queue::FileStore.new(dir)
        store.init!(%w[fail.rb])
        result = described_class.run(
          store: store,
          worker_id: "w1",
          batch: 1,
          cmd: [RbConfig.ruby, "-e", "exit 1"],
          on_failure: "requeue"
        )
        expect(result).to eq(ok: 0, fail: 1, exit_code: 1)
        expect(store.status["pending"]).to eq(1)
        expect(store.status["leases"]).to eq(0)
      end
    end

    it "returns exit code 2 on Polyrun::Error" do
      store = instance_double(Polyrun::Queue::FileStore)
      allow(store).to receive(:claim!).and_raise(Polyrun::Error, "broken queue")
      result = described_class.run(
        store: store,
        worker_id: "w1",
        batch: 1,
        cmd: ["true"],
        on_failure: "exit"
      )
      expect(result[:exit_code]).to eq(2)
    end
  end

  describe ".run_batch" do
    it "returns the child exit status" do
      expect(described_class.run_batch([RbConfig.ruby, "-e", "exit 7"], [])).to eq(7)
      expect(described_class.run_batch([RbConfig.ruby, "-e", "exit 0"], [])).to eq(0)
    end
  end
end
