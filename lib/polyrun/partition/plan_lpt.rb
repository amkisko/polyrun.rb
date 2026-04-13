require_relative "min_heap"

module Polyrun
  module Partition
    # LPT greedy binpack for cost strategies (extracted from {Plan} for size limits).
    class PlanLptBuckets
      def initialize(plan)
        @plan = plan
      end

      def build
        buckets = Array.new(@plan.total_shards) { [] }
        totals = Array.new(@plan.total_shards, 0.0)
        lpt_fill_forced!(buckets, totals)
        lpt_balance_free!(buckets, totals)
        buckets
      end

      private

      def lpt_fill_forced!(buckets, totals)
        @plan.items.each do |item|
          next unless @plan.constraints && (j = @plan.constraints.forced_shard_for(item))

          j = Integer(j)
          raise Polyrun::Error, "constraint shard #{j} out of range" if j < 0 || j >= @plan.total_shards

          buckets[j] << item
          totals[j] += @plan.send(:weight_for, item)
        end
      end

      def lpt_balance_free!(buckets, totals)
        free = @plan.items.reject { |item| @plan.constraints&.forced_shard_for(item) }
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
