require_relative "min_heap"

module Polyrun
  module Partition
    # LPT greedy binpack for cost strategies (extracted from {Plan} for size limits).
    class PlanLptBuckets
      def initialize(plan)
        @plan = plan
      end

      def build
        if @plan.stable_strategy? && @plan.stable_assignment_map&.any?
          stable = build_from_stable_map
          return stable if imbalance_ratio(stable) <= @plan.stable_imbalance_threshold
        end

        buckets = Array.new(@plan.total_shards) { [] }
        totals = Array.new(@plan.total_shards, 0.0)
        forced_pairs, free = partition_forced_and_free
        lpt_apply_forced!(buckets, totals, forced_pairs)
        lpt_balance_free!(buckets, totals, free)
        buckets
      end

      def build_from_stable_map
        buckets = Array.new(@plan.total_shards) { [] }
        map = @plan.stable_assignment_map
        @plan.items.each do |item|
          key = @plan.send(:cost_lookup_key, item)
          j = map[key]
          j = Integer(j) if j
          j = fallback_shard_for(item) unless j && j >= 0 && j < @plan.total_shards
          buckets[j] << item
        end
        buckets
      end

      def fallback_shard_for(item)
        Hrw.shard_for(path: item, total_shards: @plan.total_shards, seed: @plan.send(:hrw_salt))
      end

      def imbalance_ratio(buckets)
        totals = buckets.map { |paths| paths.sum { |p| @plan.send(:weight_for, p) } }
        return 1.0 if totals.empty?

        avg = totals.sum / totals.size.to_f
        return 1.0 unless avg.positive?

        totals.max / avg
      end

      private

      def partition_forced_and_free
        forced_pairs = []
        free = []
        @plan.items.each do |item|
          if @plan.constraints && (j = @plan.constraints.forced_shard_for(item))
            forced_pairs << [item, Integer(j)]
          else
            free << item
          end
        end
        [forced_pairs, free]
      end

      def lpt_apply_forced!(buckets, totals, forced_pairs)
        forced_pairs.each do |item, j|
          raise Polyrun::Error, "constraint shard #{j} out of range" if j < 0 || j >= @plan.total_shards

          buckets[j] << item
          totals[j] += @plan.send(:weight_for, item)
        end
      end

      def lpt_balance_free!(buckets, totals, free)
        pairs = free.map { |p| [p, @plan.send(:weight_for, p)] }
        pairs.sort_by! { |(p, w)| [-w, p] }

        heap = MinHeap.new
        @plan.total_shards.times { |j| heap.push(totals[j], j) }

        pairs.each do |path, w|
          load, j = heap.pop_min
          buckets[j] << path
          heap.push(load + w, j)
        end
      end
    end
  end
end
