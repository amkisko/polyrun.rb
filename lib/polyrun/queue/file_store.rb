require "fileutils"
require "json"
require "securerandom"
require "time"
module Polyrun
  module Queue
    # File-backed queue (spec_queue.md): +queue.json+, +pending/*.json+ chunks, +done.jsonl+, +leases.json+ (OS flock).
    class FileStore
      CHUNK_SIZE = 500

      attr_reader :root

      def initialize(root)
        @root = File.expand_path(root)
      end

      def init!(items)
        FileUtils.mkdir_p(@root)
        raise Polyrun::Error, "queue already exists: #{queue_path}" if File.file?(queue_path)

        items = items.map(&:to_s)
        meta = base_meta(items.size)
        FileUtils.mkdir_p(pending_dir)
        write_pending_chunks!(items, meta)
        atomic_write(queue_path, JSON.generate(meta))
        atomic_write(ledger_path, "")
        true
      end

      def claim!(worker_id:, batch_size:)
        batch_size = Integer(batch_size)
        raise Polyrun::Error, "batch_size must be >= 1" if batch_size < 1

        lease_id = SecureRandom.uuid
        batch = []
        with_lock do
          meta = load_meta!
          batch = take_pending_batch!(meta, batch_size)
          leases = read_leases
          leases[lease_id] = {
            "worker_id" => worker_id.to_s,
            "paths" => batch,
            "claimed_at" => Time.now.utc.iso8601
          }
          write_meta!(meta)
          write_leases!(leases)
          append_ledger(
            "CLAIM" => lease_id,
            "worker_id" => worker_id.to_s,
            "paths" => batch,
            "pending_remaining" => meta["pending_count"]
          )
        end
        {"lease_id" => lease_id, "paths" => batch}
      end

      def ack!(lease_id:, worker_id:)
        with_lock do
          leases = read_leases
          lease = leases[lease_id]
          raise Polyrun::Error, "unknown lease: #{lease_id}" unless lease

          if lease["worker_id"].to_s != worker_id.to_s
            raise Polyrun::Error, "lease worker mismatch"
          end

          leases.delete(lease_id)
          write_leases!(leases)

          paths = lease["paths"] || []
          meta = load_meta!
          meta["done_count"] = Integer(meta["done_count"]) + paths.size
          append_done_lines!(paths)
          write_meta!(meta)
          append_ledger("ACK" => lease_id, "worker_id" => worker_id.to_s, "paths" => paths)
        end
        true
      end

      def status
        with_lock do
          meta = load_meta!
          {
            "pending" => Integer(meta["pending_count"]),
            "done" => Integer(meta["done_count"]),
            "leases" => read_leases.keys.size
          }
        end
      end

      private

      def queue_path
        File.join(@root, "queue.json")
      end

      def leases_path
        File.join(@root, "leases.json")
      end

      def ledger_path
        File.join(@root, "ledger.jsonl")
      end

      def lock_path
        File.join(@root, "lock")
      end

      def pending_dir
        File.join(@root, "pending")
      end

      def done_path
        File.join(@root, "done.jsonl")
      end

      def with_lock
        FileUtils.mkdir_p(@root)
        File.open(lock_path, File::CREAT | File::RDWR) do |f|
          f.flock(File::LOCK_EX)
          yield
        end
      end

      def base_meta(pending_count)
        {
          "created_at" => Time.now.utc.iso8601,
          "pending_count" => pending_count,
          "done_count" => 0,
          "chunk_size" => CHUNK_SIZE
        }
      end

      def meta_chunk_size(meta)
        (meta["chunk_size"] || CHUNK_SIZE).to_i
      end

      def load_meta!
        p = queue_path
        raise Polyrun::Error, "queue not initialized; run queue init" unless File.file?(p)

        data = JSON.parse(File.read(p))
        raise Polyrun::Error, "invalid queue.json: #{p}" unless meta_ok?(data)

        data
      end

      def meta_ok?(data)
        data.is_a?(Hash) &&
          data.key?("pending_count") &&
          data.key?("done_count") &&
          data.key?("chunk_size")
      end

      def write_pending_chunks!(items, meta)
        chunk_size = meta_chunk_size(meta)
        FileUtils.mkdir_p(pending_dir)
        items.each_slice(chunk_size).with_index(1) do |slice, idx|
          atomic_write(File.join(pending_dir, format("%06d.json", idx)), JSON.generate(slice))
        end
      end

      def write_meta!(meta)
        atomic_write(queue_path, JSON.generate(meta))
      end

      def append_done_lines!(paths)
        return if paths.empty?

        File.open(done_path, "a") do |io|
          paths.each { |p| io.puts(JSON.generate(p.to_s)) }
        end
      end

      def read_leases
        return {} unless File.file?(leases_path)

        JSON.parse(File.read(leases_path))
      end

      def write_leases!(h)
        atomic_write(leases_path, JSON.generate(h))
      end

      def append_ledger(entry)
        line = JSON.generate(entry.merge("at" => Time.now.utc.iso8601)) + "\n"
        File.open(ledger_path, "a") { |f| f.write(line) }
      end

      def atomic_write(path, body)
        tmp = "#{path}.tmp.#{$$}"
        File.write(tmp, body)
        File.rename(tmp, path)
      end
    end
  end
end

require_relative "file_store_pending"
