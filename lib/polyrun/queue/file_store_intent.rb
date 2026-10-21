# rubocop:disable Metrics/ModuleLength -- claim/ack/reclaim intent recovery beside FileStore
module Polyrun
  module Queue
    class FileStore
      INTENT_BASENAME = "intent.json"

      private

      def intent_path
        File.join(@root, INTENT_BASENAME)
      end

      def write_intent!(payload)
        atomic_write(intent_path, JSON.generate(payload), fsync: true)
      end

      def clear_intent!
        File.unlink(intent_path)
      rescue Errno::ENOENT
        nil
      end

      def recover_intent!
        return unless File.file?(intent_path)

        intent = JSON.parse(File.read(intent_path))
        case intent["op"].to_s
        when "claim"
          recover_claim_intent!(intent)
        when "ack", "ack_paths"
          recover_ack_intent!(intent)
        when "reclaim", "reclaim_lease"
          recover_reclaim_intent!(intent)
        else
          Polyrun::Log.warn "polyrun queue: dropping unknown intent op=#{intent["op"].inspect}"
        end
        clear_intent!
      rescue JSON::ParserError, TypeError
        Polyrun::Log.warn "polyrun queue: dropping corrupt intent at #{intent_path}"
        clear_intent!
      end

      def recover_claim_intent!(intent)
        lease_id = intent["lease_id"].to_s
        leases = read_leases
        return if leases.key?(lease_id)

        paths = Array(intent["paths"])
        meta = load_meta!
        return_paths_to_pending!(meta, paths)
        write_meta!(meta)
        append_ledger(
          "RECOVER_CLAIM" => lease_id,
          "worker_id" => intent["worker_id"],
          "paths" => paths
        )
      end

      def recover_ack_intent!(intent)
        lease_id = intent["lease_id"].to_s
        leases = read_leases
        lease = leases[lease_id]
        return unless lease

        paths = Array(intent["paths"])
        paths = Array(lease["paths"]) if paths.empty?
        apply_ack_side_effects!(leases, lease_id, lease, paths, intent["worker_id"])
      end

      def recover_reclaim_intent!(intent)
        lease_id = intent["lease_id"].to_s
        leases = read_leases
        lease = leases[lease_id]
        return unless lease

        paths = Array(intent["paths"])
        paths = Array(lease["paths"]) if paths.empty?
        bumped = lease.merge("attempts" => intent["attempts"] || lease["attempts"])
        leases.delete(lease_id)
        write_leases!(leases)
        meta = load_meta!
        quarantine_or_return_paths!(meta, paths, bumped)
        write_meta!(meta)
        append_ledger(
          "RECOVER_RECLAIM" => lease_id,
          "worker_id" => lease["worker_id"],
          "paths" => paths,
          "attempts" => bumped["attempts"]
        )
      end

      def apply_ack_side_effects!(leases, lease_id, lease, paths, worker_id)
        append_done_lines!(paths)
        clear_path_attempts!(paths)
        meta = load_meta!
        meta["done_count"] = Integer(meta["done_count"]) + paths.size
        write_meta!(meta)
        remaining = Array(lease["paths"]).map(&:to_s) - paths.map(&:to_s)
        if remaining.empty?
          leases.delete(lease_id)
        else
          lease["paths"] = remaining
          leases[lease_id] = lease
        end
        write_leases!(leases)
        append_ledger("ACK" => lease_id, "worker_id" => worker_id.to_s, "paths" => paths)
      end

      def quarantine_or_return_paths!(meta, paths, lease)
        attempts_h = read_path_attempts
        to_pending = []
        poisoned = []
        max_attempts = queue_max_attempts
        Array(paths).each do |path|
          key = path.to_s
          n = Integer(attempts_h[key] || 0) + 1
          attempts_h[key] = n
          if max_attempts.positive? && n >= max_attempts
            poisoned << [key, n]
          else
            to_pending << key
          end
        end
        write_path_attempts!(attempts_h)
        poisoned.each do |key, n|
          append_failed_lines!(
            [key],
            "worker_id" => lease["worker_id"],
            "attempts" => n
          )
          append_ledger("POISON" => lease["worker_id"], "attempts" => n, "paths" => [key])
        end
        return_paths_to_pending!(meta, to_pending)
      end

      def clear_path_attempts!(paths)
        attempts_h = read_path_attempts
        Array(paths).each { |p| attempts_h.delete(p.to_s) }
        write_path_attempts!(attempts_h)
      end

      def queue_max_attempts
        raw = ENV["POLYRUN_QUEUE_MAX_ATTEMPTS"].to_s.strip
        return 3 if raw.empty?

        n = Integer(raw, exception: false)
        n && n >= 1 ? n : 3
      end

      def path_attempts_path
        File.join(@root, "path_attempts.json")
      end

      def read_path_attempts
        return {} unless File.file?(path_attempts_path)

        data = JSON.parse(File.read(path_attempts_path))
        data.is_a?(Hash) ? data : {}
      rescue JSON::ParserError
        {}
      end

      def write_path_attempts!(hash)
        atomic_write(path_attempts_path, JSON.generate(hash))
      end

      def failed_path
        File.join(@root, "failed.jsonl")
      end

      def append_failed_lines!(paths, lease)
        return if paths.empty?

        File.open(failed_path, "a") do |io|
          paths.each do |p|
            io.puts(JSON.generate(
              "path" => p.to_s,
              "worker_id" => lease["worker_id"],
              "attempts" => Integer(lease["attempts"] || 0),
              "at" => Time.now.utc.iso8601
            ))
          end
        end
      end
    end
  end
end
# rubocop:enable Metrics/ModuleLength
