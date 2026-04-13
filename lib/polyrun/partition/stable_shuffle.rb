module Polyrun
  module Partition
    # Deterministic Fisher–Yates shuffle (spec_queue.md).
    module StableShuffle
      module_function

      def call(items, seed)
        rng = Random.new(Integer(seed))
        a = items.dup
        (a.size - 1).downto(1) do |i|
          j = rng.rand(i + 1)
          a[i], a[j] = a[j], a[i]
        end
        a
      end
    end
  end
end
