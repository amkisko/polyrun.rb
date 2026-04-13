require_relative "hrw"

module Polyrun
  module Partition
    class Plan
      def hrw_shards
        @hrw_shards ||= begin
          buckets = Array.new(total_shards) { [] }
          salt = hrw_salt
          items.each do |path|
            j =
              if @constraints && (fj = @constraints.forced_shard_for(path))
                Integer(fj)
              else
                Hrw.shard_for(path: path, total_shards: total_shards, seed: salt)
              end
            raise Polyrun::Error, "constraint shard out of range" if j < 0 || j >= total_shards

            buckets[j] << path
          end
          buckets
        end
      end

      # One pass over +ordered_items+ (round_robin / random_round_robin); avoids O(workers × n) rescans in +shard+.
      def mod_shards
        @mod_shards ||= begin
          list = ordered_items
          buckets = Array.new(total_shards) { [] }
          list.each_with_index { |path, i| buckets[i % total_shards] << path }
          buckets
        end
      end

      def hrw_salt
        s = seed
        (s.nil? || s.to_s.empty?) ? "polyrun-hrw" : s.to_s
      end

      def random_seed
        s = seed
        return Integer(s) if s && s != ""

        0
      end
    end
  end
end
