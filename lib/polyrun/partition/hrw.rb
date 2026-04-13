require "digest"

module Polyrun
  module Partition
    # Rendezvous / highest-hash shard assignment (spec_queue.md): stateless, stable when m changes.
    module Hrw
      module_function

      # @return [Integer] shard index in 0...m
      def shard_for(path:, total_shards:, seed: "")
        m = Integer(total_shards)
        raise Polyrun::Error, "total_shards must be >= 1" if m < 1

        best_j = 0
        best = -1
        salt = seed.to_s
        p = path.to_s
        m.times do |j|
          h = score(p, j, salt)
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
