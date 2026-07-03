# rubocop:disable Polyrun/FileLength, Metrics/ModuleLength -- report analysis + text formatting
module Polyrun
  module SpecQuality
    # Human-readable spec quality report from merged JSON.
    module Report
      module_function

      # rubocop:disable Metrics/AbcSize -- merged example analysis
      def analyze(merged, cfg = {}, plan_shards: nil)
        cfg = default_cfg(cfg)
        examples = merged["examples"] || {}
        hot_lines = merged["hot_lines"] || {}
        shard_summary = merged["shard_summary"] || Merge.shard_summary(examples)

        zero_hit = examples.select { |_loc, row| row["unique_lines"].to_i.zero? }
        churn = examples.select { |_loc, row| row["line_churn"].to_i >= cfg["min_line_churn"] }
          .sort_by { |_loc, row| -row["line_churn"].to_i }
        hot = hot_lines.select { |_line, h| h["example_count"].to_i >= cfg["hot_line_example_overlap"] }
          .sort_by { |_line, h| [-h["example_count"].to_i, -h["total_hits"].to_i] }

        outliers = build_outliers(examples, cfg)
        partition_hints = partition_hints_for(hot, examples, plan_shards) if plan_shards && !plan_shards.empty?

        {
          zero_hit: zero_hit,
          line_churn: churn,
          hot_lines: hot,
          outliers: outliers,
          shard_summary: shard_summary,
          partition_hints: partition_hints,
          config: cfg
        }
      end
      # rubocop:enable Metrics/AbcSize

      def format_report(merged, cfg: {}, top: 30, profile: nil, plan_shards: nil)
        analysis = analyze(merged, cfg, plan_shards: plan_shards)
        lines = ["Polyrun spec quality report", ""]

        lines.concat(format_shard_summary_section(analysis[:shard_summary]))
        lines << ""
        lines.concat(format_zero_hit_section(analysis[:zero_hit], top))
        lines << ""
        lines.concat(format_hot_lines_section(analysis[:hot_lines], top))
        lines << ""
        lines.concat(format_churn_section(analysis[:line_churn], top))
        hints_section = format_partition_hints_section(analysis[:partition_hints], top)
        unless hints_section.empty?
          lines << ""
          lines.concat(hints_section)
        end
        lines << ""
        lines.concat(format_outliers_section(analysis[:outliers], top, profile))

        lines.join("\n") + "\n"
      end

      def gate_violations(merged, cfg = {})
        cfg = default_cfg(cfg)
        analysis = analyze(merged, cfg)
        violations = []

        max_zero = cfg["max_zero_hit_examples"]
        if max_zero && analysis[:zero_hit].size > max_zero.to_i
          violations << "zero_hit_examples=#{analysis[:zero_hit].size} max=#{max_zero}"
        end

        min_unique = cfg["minimum_unique_lines_per_example"]
        if min_unique
          bad = analysis[:zero_hit].keys
          if bad.size.positive?
            violations << "examples_below_minimum_unique_lines=#{bad.size} minimum=#{min_unique}"
          end
        end

        max_hot = cfg["max_hot_line_overlap"]
        if max_hot
          over = analysis[:hot_lines].count { |_k, h| h["example_count"].to_i > max_hot.to_i }
          violations << "hot_line_overlap_count=#{over} max=#{max_hot}" if over.positive?
        end

        violations
      end

      def emit_warnings!(merged, cfg = {})
        analyze(merged, cfg).fetch(:line_churn, {}).each do |loc, row|
          Polyrun::Log.warn "polyrun spec-quality line_churn: #{loc} churn=#{row["line_churn"]}"
        end
      end

      def default_cfg(cfg)
        h = cfg.is_a?(Hash) ? cfg.transform_keys(&:to_s) : {}
        SpecQuality::Config::DEFAULTS.merge(h)
      end

      def format_shard_summary_section(shard_summary)
        lines = ["Shard attribution:"]
        if shard_summary.nil? || shard_summary.empty?
          lines << "  (none)"
          return lines
        end

        shard_summary.sort_by { |k, _| k.to_s }.each do |shard, stats|
          lines << format(
            "  shard %s — examples=%d zero_hit=%d line_churn=%d",
            shard,
            stats["examples"],
            stats["zero_hit"],
            stats["line_churn"]
          )
        end
        lines
      end

      def format_partition_hints_section(hints, top)
        return [] if hints.nil? || hints.empty?

        lines = ["Partition hints (hot lines × shard):"]
        hints.first(top).each do |h|
          lines << format("  %s — shard %s (%d examples)", h[:line], h[:shard], h[:example_count])
        end
        lines << "  …" if hints.size > top
        lines
      end

      def partition_hints_for(hot_lines, examples, plan_shards)
        hot_lines.filter_map do |line, h|
          example_locs = h["examples"] || []
          shard_counts = Hash.new(0)
          example_locs.each do |loc|
            s = PlanLoader.shard_for_example(loc, plan_shards) || examples.dig(loc, "polyrun_shard_index")&.to_s
            shard_counts[s] += 1 if s
          end
          next if shard_counts.empty?

          shard, count = shard_counts.max_by { |_s, n| n }
          {line: line, shard: shard, example_count: count, total_hits: h["total_hits"]}
        end.sort_by { |h| [-h[:example_count], -h[:total_hits]] }
      end

      def format_zero_hit_section(zero_hit, top)
        lines = ["Zero production lines (#{zero_hit.size} examples):"]
        if zero_hit.empty?
          lines << "  (none)"
          return lines
        end

        zero_hit.keys.sort.first(top).each { |loc| lines << "  #{loc}" }
        lines << "  …" if zero_hit.size > top
        lines
      end

      def format_hot_lines_section(hot_lines, top)
        lines = ["Hot lines (shared across examples):"]
        if hot_lines.empty?
          lines << "  (none)"
          return lines
        end

        hot_lines.first(top).each do |line, h|
          lines << format("  %s — %d examples, %d cumulative hits", line, h["example_count"], h["total_hits"])
        end
        lines << "  …" if hot_lines.size > top
        lines
      end

      def format_churn_section(churn_rows, top)
        lines = ["Per-example line churn (top #{[top, churn_rows.size].min}):"]
        if churn_rows.empty?
          lines << "  (none)"
          return lines
        end

        churn_rows.first(top).each do |loc, row|
          lines << format("  %s — churn=%d max_line=%d", loc, row["line_churn"], row["max_line_churn"])
        end
        lines
      end

      # rubocop:disable Metrics/AbcSize -- outlier row filter
      def build_outliers(examples, cfg)
        examples.filter_map do |loc, row|
          prof = row["profile"] || {}
          unique = row["unique_lines"].to_i
          wall = prof["wall"].to_f
          alloc = prof["gc_allocated"].to_i
          cpu = prof["cpu_user"].to_f + prof["cpu_system"].to_f
          sql = row["sql_count"].to_i
          factories = (row["factory_counts"] || {}).values.sum

          score = 0
          reasons = []
          if unique.zero?
            score += 10
            reasons << "zero_lines"
          end
          if wall > 1.0 && unique < 3
            score += 5
            reasons << "slow_low_coverage"
          end
          if alloc > 50_000 && wall > 0.5
            score += 3
            reasons << "high_alloc"
          end
          if cpu > 0.5 && unique < 3
            score += 3
            reasons << "high_cpu_low_coverage"
          end
          if sql >= cfg["min_query_count"]
            score += 4
            reasons << "high_sql_count"
          end
          if factories >= 10
            score += 2
            reasons << "many_factories"
          end
          next if score.zero?

          {location: loc, score: score, reasons: reasons, row: row}
        end.sort_by { |h| -h[:score] }
      end
      # rubocop:enable Metrics/AbcSize

      # rubocop:disable Metrics/AbcSize -- outlier text formatting
      def format_outliers_section(outliers, top, profile)
        lines = ["Correlated outliers (slow / empty / heavy):"]
        if outliers.empty?
          lines << "  (none)"
          return lines
        end

        dims = profile ? profile.to_s.split(",").map(&:strip) : nil
        outliers.first(top).each do |o|
          row = o[:row]
          prof = row["profile"] || {}
          detail = o[:reasons].join(", ")
          if dims.nil? || dims.empty?
            lines << format("  %s — score=%d (%s)", o[:location], o[:score], detail)
          else
            prof_bits = dims.filter_map do |d|
              case d
              when "wall" then "wall=#{format("%.2f", prof["wall"])}" if prof["wall"]
              when "cpu" then "cpu=#{format("%.2f", prof["cpu_user"].to_f + prof["cpu_system"].to_f)}"
              when "mem" then "alloc=#{prof["gc_allocated"]}" if prof["gc_allocated"]
              when "io"
                r = prof["io_read_bytes"]
                w = prof["io_write_bytes"]
                "io=#{r}/#{w}" if r || w
              end
            end
            lines << format("  %s — score=%d (%s) %s", o[:location], o[:score], detail, prof_bits.join(" "))
          end
        end
        lines << "  …" if outliers.size > top
        lines
      end
      # rubocop:enable Metrics/AbcSize
    end
  end
end
# rubocop:enable Polyrun/FileLength, Metrics/ModuleLength
