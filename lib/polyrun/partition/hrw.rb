require "digest"

module Polyrun
  module Partition
    # Rendezvous / highest-hash shard assignment (spec_queue.md): stateless, stable when m changes.
    module Hrw
      module_function

      # @return [Integer] shard index in 0...m
      def shard_for(path:, total_shards:, seed: "")
        pick_shard(path: path, total_shards: total_shards, seed: seed) { |p, j, salt| score(p, j, salt) }
      end

      # Per-shard weights (heterogeneous nodes). Uniform weights match +shard_for+.
      def weighted_shard_for(path:, total_shards:, seed: "", shard_weights: nil)
        weights = normalize_shard_weights(shard_weights, total_shards)
        pick_shard(path: path, total_shards: total_shards, seed: seed) do |p, j, salt|
          base = score(p, j, salt).to_f
          w = weights[j]
          w.positive? ? base / w : base
        end
      end

      def normalize_shard_weights(shard_weights, total_shards)
        m = Integer(total_shards)
        return Array.new(m, 1.0) if shard_weights.nil? || shard_weights.empty?

        weights = shard_weights.map { |w| w.to_f }
        if weights.size < m
          weights += Array.new(m - weights.size, 1.0)
        elsif weights.size > m
          weights = weights[0, m]
        end
        weights
      end

      def pick_shard(path:, total_shards:, seed:)
        m = Integer(total_shards)
        raise Polyrun::Error, "total_shards must be >= 1" if m < 1

        best_j = 0
        best = -1.0
        salt = seed.to_s
        p = path.to_s
        m.times do |j|
          h = yield(p, j, salt)
          if h > best
            best = h
            best_j = j
          end
        end
        best_j
      end

      def score(path, shard_index, salt)
        digest = Digest::SHA256.digest("#{salt}\n#{path}\n#{shard_index}")
        if fast_score?
          digest.unpack1("Q>")
        else
          digest.unpack1("H*").hex
        end
      end

      def fast_score?
        %w[1 true yes].include?(ENV["POLYRUN_HRW_FAST_SCORE"]&.to_s&.downcase)
      end
      private_class_method :fast_score?
    end
  end
end
