module Polyrun
  module Partition
    # Binary min-heap of [load, shard_index] for LPT placement (tie-break: lower shard index).
    class MinHeap
      def initialize
        @a = []
      end

      def push(load, shard_index)
        @a << [load.to_f, Integer(shard_index)]
        sift_up(@a.size - 1)
      end

      def pop_min
        return nil if @a.empty?

        min = @a[0]
        last = @a.pop
        @a[0] = last if @a.any?
        sift_down(0) if @a.size > 1
        min
      end

      def empty?
        @a.empty?
      end

      private

      def sift_up(i)
        while i.positive?
          p = (i - 1) / 2
          break unless less(@a[i], @a[p])

          @a[i], @a[p] = @a[p], @a[i]
          i = p
        end
      end

      def sift_down(i)
        n = @a.size
        loop do
          l = 2 * i + 1
          r = l + 1
          smallest = i
          smallest = l if l < n && less(@a[l], @a[smallest])
          smallest = r if r < n && less(@a[r], @a[smallest])
          break if smallest == i

          @a[i], @a[smallest] = @a[smallest], @a[i]
          i = smallest
        end
      end

      # Compare [load, j]: lower load wins; tie -> lower j
      def less(x, y)
        return true if x[0] < y[0]
        return false if x[0] > y[0]

        x[1] < y[1]
      end
    end
  end
end
