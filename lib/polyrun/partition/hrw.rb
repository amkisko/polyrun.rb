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

      def weighted_shard_for(path:, total_shards:, seed: "", weight: 0.0)
        pick_shard(path: path, total_shards: total_shards, seed: seed) do |p, j, salt|
          base = score(p, j, salt)
          weight.positive? ? (base.to_f / weight) : base
        end
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
        Digest::SHA256.digest("#{salt}\n#{path}\n#{shard_index}").unpack1("H*").hex
      end
    end
  end
end
