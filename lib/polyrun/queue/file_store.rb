# rubocop:disable Polyrun/FileLength, Metrics/ClassLength -- file-backed queue chunks + leases
require "fileutils"
require "json"
require "securerandom"
require "time"
module Polyrun
  module Queue
    # File-backed queue (spec_queue.md): +queue.json+, +pending/*.json+ chunks, +done.jsonl+, +leases.json+ (OS flock).
    #
    # Path lifecycle (lease transitions):
    #   init!           → paths in pending chunks only
    #   claim!          → pending −batch → active lease in leases.json
    #   ack!            → lease removed; paths appended to done.jsonl
    #   reclaim!        → stale or matching lease → paths returned to pending
    #   reclaim_lease!  → one lease by id → paths returned to pending
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

        lease_id = nil
        batch = []
        with_lock do
          meta = load_meta!
          batch = take_pending_batch!(meta, batch_size)
          unless batch.empty?
            lease_id = SecureRandom.uuid
            now = Time.now.utc.iso8601
            write_intent!(
              "op" => "claim",
              "lease_id" => lease_id,
              "worker_id" => worker_id.to_s,
              "paths" => batch
            )
            leases = read_leases
            leases[lease_id] = {
              "worker_id" => worker_id.to_s,
              "paths" => batch,
              "claimed_at" => now,
              "heartbeat_at" => now,
              "attempts" => 0
            }
            write_meta!(meta)
            write_leases!(leases)
            clear_intent!
            append_ledger(
              "CLAIM" => lease_id,
              "worker_id" => worker_id.to_s,
              "paths" => batch,
              "pending_remaining" => meta["pending_count"]
            )
          end
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

          paths = lease["paths"] || []
          write_intent!(
            "op" => "ack",
            "lease_id" => lease_id,
            "worker_id" => worker_id.to_s,
            "paths" => paths
          )
          # done.jsonl before removing the lease so a crash still has durable completion evidence.
          append_done_lines!(paths)
          meta = load_meta!
          meta["done_count"] = Integer(meta["done_count"]) + paths.size
          write_meta!(meta)
          leases.delete(lease_id)
          write_leases!(leases)
          clear_intent!
          append_ledger("ACK" => lease_id, "worker_id" => worker_id.to_s, "paths" => paths)
        end
        true
      end

      # Marks a subset of a lease's paths done; removes the lease when none remain.
      def ack_paths!(lease_id:, worker_id:, paths:)
        paths = Array(paths).map(&:to_s)
        raise Polyrun::Error, "ack_paths! requires at least one path" if paths.empty?

        with_lock do
          leases = read_leases
          lease = leases[lease_id]
          raise Polyrun::Error, "unknown lease: #{lease_id}" unless lease

          if lease["worker_id"].to_s != worker_id.to_s
            raise Polyrun::Error, "lease worker mismatch"
          end

          held = Array(lease["paths"]).map(&:to_s)
          unknown = paths - held
          raise Polyrun::Error, "ack_paths! paths not on lease: #{unknown.join(", ")}" unless unknown.empty?

          write_intent!(
            "op" => "ack_paths",
            "lease_id" => lease_id,
            "worker_id" => worker_id.to_s,
            "paths" => paths
          )
          apply_ack_side_effects!(leases, lease_id, lease, paths, worker_id)
          clear_intent!
        end
        true
      end

      def heartbeat!(lease_id:, worker_id:)
        with_lock do
          leases = read_leases
          lease = leases[lease_id]
          raise Polyrun::Error, "unknown lease: #{lease_id}" unless lease

          if lease["worker_id"].to_s != worker_id.to_s
            raise Polyrun::Error, "lease worker mismatch"
          end

          lease["heartbeat_at"] = Time.now.utc.iso8601
          leases[lease_id] = lease
          write_leases!(leases)
        end
        true
      end

      def status(detailed: false)
        with_lock do
          meta = load_meta!
          leases = read_leases
          base = {
            "pending" => Integer(meta["pending_count"]),
            "done" => Integer(meta["done_count"]),
            "leases" => leases.keys.size
          }
          return base unless detailed

          base.merge("lease_details" => lease_details(leases))
        end
      end

      # Reclaim leases older than +older_than+ seconds and/or matching +worker_id+ when set.
      # @return [Integer] number of paths returned to pending
      def reclaim!(older_than: nil, worker_id: nil)
        reclaimed_paths = 0
        with_lock do
          meta = load_meta!
          leases = read_leases
          keep = {}
          leases.each do |lease_id, lease|
            if reclaim_lease?(lease, older_than: older_than, worker_id: worker_id)
              paths = lease["paths"] || []
              bumped = lease.merge("attempts" => Integer(lease["attempts"] || 0) + 1)
              write_intent!(
                "op" => "reclaim",
                "lease_id" => lease_id,
                "worker_id" => lease["worker_id"],
                "paths" => paths,
                "attempts" => bumped["attempts"]
              )
              quarantine_or_return_paths!(meta, paths, bumped)
              reclaimed_paths += paths.size
              append_ledger(
                "RECLAIM" => lease_id,
                "worker_id" => lease["worker_id"],
                "paths" => paths,
                "attempts" => bumped["attempts"]
              )
              clear_intent!
            else
              keep[lease_id] = lease
            end
          end
          write_leases!(keep)
          write_meta!(meta)
        end
        reclaimed_paths
      end

      def reclaim_lease!(lease_id)
        reclaimed = 0
        with_lock do
          leases = read_leases
          lease = leases[lease_id]
          return 0 unless lease

          paths = lease["paths"] || []
          bumped = lease.merge("attempts" => Integer(lease["attempts"] || 0) + 1)
          write_intent!(
            "op" => "reclaim_lease",
            "lease_id" => lease_id,
            "worker_id" => lease["worker_id"],
            "paths" => paths,
            "attempts" => bumped["attempts"]
          )
          leases.delete(lease_id)
          write_leases!(leases)
          meta = load_meta!
          quarantine_or_return_paths!(meta, paths, bumped)
          write_meta!(meta)
          reclaimed = paths.size
          append_ledger(
            "RECLAIM" => lease_id,
            "worker_id" => lease["worker_id"],
            "paths" => paths,
            "attempts" => bumped["attempts"]
          )
          clear_intent!
        end
        reclaimed
      end

      private

      def reclaim_lease?(lease, older_than:, worker_id:)
        if worker_id && lease["worker_id"].to_s != worker_id.to_s
          return false
        end
        if older_than
          stamp = lease["heartbeat_at"].to_s
          stamp = lease["claimed_at"].to_s if stamp.empty?
          touched = Time.parse(stamp)
          return (Time.now - touched) >= older_than
        end
        !!worker_id
      rescue ArgumentError
        true
      end

      def lease_details(leases)
        now = Time.now
        leases.map do |lease_id, lease|
          stamp = lease["heartbeat_at"].to_s
          stamp = lease["claimed_at"].to_s if stamp.empty?
          touched = Time.parse(stamp)
          {
            "lease_id" => lease_id,
            "worker_id" => lease["worker_id"],
            "paths_count" => (lease["paths"] || []).size,
            "claimed_at" => lease["claimed_at"],
            "heartbeat_at" => lease["heartbeat_at"],
            "age_seconds" => (now - touched).round(1)
          }
        rescue ArgumentError
          {
            "lease_id" => lease_id,
            "worker_id" => lease["worker_id"],
            "paths_count" => (lease["paths"] || []).size,
            "claimed_at" => lease["claimed_at"],
            "heartbeat_at" => lease["heartbeat_at"],
            "age_seconds" => nil
          }
        end
      end

      def return_paths_to_pending!(meta, paths)
        return if paths.empty?

        meta["pending_count"] = Integer(meta["pending_count"]) + paths.size
        files = sorted_chunk_files
        if files.empty?
          FileUtils.mkdir_p(pending_dir)
          atomic_write(File.join(pending_dir, "000001.json"), JSON.generate(paths.map(&:to_s)))
        else
          head = files.first
          chunk = JSON.parse(File.read(head))
          chunk = paths.map(&:to_s) + chunk
          atomic_write(head, JSON.generate(chunk))
        end
      end

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
          recover_intent!
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

      def atomic_write(path, body, fsync: false)
        tmp = "#{path}.tmp.#{$$}"
        File.open(tmp, File::WRONLY | File::CREAT | File::TRUNC) do |io|
          io.write(body)
          io.flush
          io.fsync if fsync
        end
        File.rename(tmp, path)
      end
    end
  end
end

require_relative "file_store_pending"
require_relative "file_store_intent"
# rubocop:enable Polyrun/FileLength, Metrics/ClassLength
