module Polyrun
  module Partition
    # Imbalance and dominant-file reports from {Plan} shard weights.
    module Reports
      IMBALANCE_WARN = 1.20
      IMBALANCE_ATTENTION = 1.50
      DOMINANT_SHARD_FRACTION = 0.40

      module_function

      def emit_all!(plan)
        totals = plan.shard_weight_totals
        return if totals.empty? || totals.all?(&:zero?)

        emit_imbalance!(plan, totals)
        emit_dominant_files!(plan, totals)
      end

      def imbalance_metrics(totals)
        return nil if totals.empty?

        max = totals.max
        min = totals.min
        avg = totals.sum / totals.size.to_f
        ratio = avg.positive? ? max / avg : 1.0
        slowest = totals.each_with_index.max_by { |v, _| v }&.last
        {
          max_shard_seconds: max,
          min_shard_seconds: min,
          avg_shard_seconds: avg,
          imbalance_ratio: ratio,
          slowest_shard: slowest
        }
      end

      def emit_imbalance!(plan, totals = nil)
        totals ||= plan.shard_weight_totals
        m = imbalance_metrics(totals)
        return unless m

        lines = []
        lines << "polyrun partition imbalance:"
        lines << format(
          "  max=%.2fs min=%.2fs avg=%.2fs imbalance_ratio=%.2f slowest_shard=%d",
          m[:max_shard_seconds],
          m[:min_shard_seconds],
          m[:avg_shard_seconds],
          m[:imbalance_ratio],
          m[:slowest_shard]
        )

        slow_idx = m[:slowest_shard]
        slow_paths = plan.shard(slow_idx)
        slow_total = totals[slow_idx]
        if slow_total.positive? && slow_paths.any?
          top = plan.shard_file_weights(slow_idx).first
          if top
            _path, w = top
            pct = (w / slow_total) * 100.0
            lines << format("  largest_file_percent_of_shard=%.1f%%", pct)
            if pct > DOMINANT_SHARD_FRACTION * 100.0
              lines << "  hint: single file dominates slowest shard; try --timing-granularity example or split the file"
            end
          end
        end

        plan.total_shards.times do |i|
          top5 = plan.shard_file_weights(i).first(5)
          next if top5.empty?

          lines << "  shard #{i} top files:"
          top5.each do |path, w|
            lines << format("    %.2fs  %s", w, path)
          end
        end

        if m[:imbalance_ratio] > IMBALANCE_ATTENTION
          lines << "  Attention required: slowest shard is #{format('%.2f', m[:imbalance_ratio])}x average"
        elsif m[:imbalance_ratio] > IMBALANCE_WARN
          lines << "  Warning: imbalance_ratio > #{IMBALANCE_WARN}"
        end

        lines.each { |ln| Polyrun::Log.warn ln }
      end

      def dominant_candidates(plan, totals = nil)
        totals ||= plan.shard_weight_totals
        return [] if totals.empty?

        suite_total = totals.sum
        return [] if suite_total <= 0

        target = suite_total / plan.total_shards.to_f
        slow_idx = totals.each_with_index.max_by { |v, _| v }&.last
        slow_total = slow_idx ? totals[slow_idx] : 0.0

        weights = file_weights_aggregated(plan)
        weights.filter_map do |path, w|
          next if w <= target

          mult = w / target
          reasons = []
          reasons << "#{format('%.1f', mult)}x target shard time" if mult > 1.0
          reasons << "split candidate" if slow_total.positive? && w > DOMINANT_SHARD_FRACTION * slow_total
          {path: path, seconds: w, target: target, multiple: mult, reasons: reasons}
        end.sort_by { |h| -h[:seconds] }
      end

      def emit_dominant_files!(plan, totals = nil)
        candidates = dominant_candidates(plan, totals)
        return if candidates.empty?

        Polyrun::Log.warn "Attention:"
        candidates.first(10).each do |c|
          Polyrun::Log.warn format("  %s: %.1fs", c[:path], c[:seconds])
          Polyrun::Log.warn format("  This single file is %.1fx the target shard time.", c[:multiple])
          Polyrun::Log.warn "  Try --timing-granularity example or split this file."
        end
      end

      def file_weights_aggregated(plan)
        by_file = Hash.new(0.0)
        plan.items.each do |p|
          w = plan.file_weight(p)
          key =
            if plan.timing_granularity == :example
              TimingDiagnostics.file_from_locator(p.to_s)
            else
              p.to_s
            end
          by_file[key] += w
        end
        by_file
      end
    end
  end
end
