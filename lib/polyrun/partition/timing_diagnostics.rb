module Polyrun
  module Partition
    # Stale / missing timing coverage before cost-based partition.
    module TimingDiagnostics
      SUSPICIOUS_BASENAME = /system|feature|integration|playwright|capybara/i.freeze

      module_function

      # @return [Hash] analysis result with :missing_files, :stale_entries, :coverage, etc.
      def analyze(items:, costs:, timing_path:, root:, granularity: :file)
        root = File.expand_path(root || Dir.pwd)
        g = TimingKeys.normalize_granularity(granularity)
        item_keys = items.map { |p| lookup_key(p, root, g) }
        cost_keys = costs&.keys || []

        if g == :example
          item_file_keys = item_keys.map { |k| file_from_locator(k) }.uniq
          cost_file_keys = cost_keys.map { |k| file_from_locator(k) }.uniq
          known = item_file_keys.count { |k| cost_file_keys.include?(k) || item_keys.any? { |ik| cost_keys.include?(ik) } }
          missing = item_keys.reject { |k| cost_keys.include?(k) }
          stale = cost_keys.reject { |k| item_keys.include?(k) }
          total = item_keys.size
        else
          known = item_keys.count { |k| costs&.key?(k) }
          missing = item_keys.reject { |k| costs&.key?(k) }
          stale = cost_keys.reject { |k| item_keys.include?(k) }
          total = item_keys.size
        end

        coverage = total.zero? ? 1.0 : known.to_f / total
        default_weight = default_weight_for(costs)
        suspicious = missing.select { |k| suspicious_path?(k) }

        {
          missing_files: missing,
          stale_entries: stale,
          coverage: coverage,
          known_files: known,
          total_files: total,
          timing_file_age: timing_file_age(timing_path),
          default_weight: default_weight,
          suspicious_missing: suspicious
        }
      end

      def emit_warnings!(analysis)
        cov = analysis[:coverage]
        if cov < 0.50
          Polyrun::Log.warn "polyrun: timing coverage #{format_percent(cov)} — binpack quality low; run full timing capture first"
        elsif cov < 0.80
          Polyrun::Log.warn "polyrun: timing coverage #{format_percent(cov)} (< 80%)"
        end

        dw = analysis[:default_weight]
        Polyrun::Log.warn "polyrun: default weight for missing files: #{format('%.4f', dw)}s (mean of known costs)"

        if analysis[:timing_file_age]
          Polyrun::Log.warn "polyrun: timing file age: #{analysis[:timing_file_age]}"
        end

        missing = analysis[:missing_files]
        unless missing.empty?
          Polyrun::Log.warn "polyrun: #{missing.size} file(s) without timing data"
          missing.first(10).each { |p| Polyrun::Log.warn "  missing: #{p}" }
          Polyrun::Log.warn "  ..." if missing.size > 10
        end

        stale = analysis[:stale_entries]
        unless stale.empty?
          Polyrun::Log.warn "polyrun: #{stale.size} timing entry(ies) for files not in suite"
          stale.first(5).each { |p| Polyrun::Log.warn "  stale: #{p}" }
          Polyrun::Log.warn "  ..." if stale.size > 5
        end

        suspicious = analysis[:suspicious_missing]
        return if suspicious.empty?

        Polyrun::Log.warn "polyrun: suspicious missing timing (#{suspicious.size} slow-path pattern(s)):"
        suspicious.first(5).each { |p| Polyrun::Log.warn "  suspicious: #{p}" }
      end

      def lookup_key(path, root, granularity)
        TimingKeys.normalize_locator(path.to_s, root, granularity)
      end

      def file_from_locator(key)
        s = key.to_s
        m = s.match(/\A(.+):(\d+)\z/)
        m ? m[1] : s
      end

      def suspicious_path?(key)
        base = File.basename(file_from_locator(key))
        base.match?(SUSPICIOUS_BASENAME)
      end

      def default_weight_for(costs)
        vals = costs&.values || []
        return 1.0 if vals.empty?

        vals.sum / vals.size.to_f
      end

      def timing_file_age(timing_path)
        return nil unless timing_path

        abs = File.expand_path(timing_path.to_s, Dir.pwd)
        return nil unless File.file?(abs)

        age_sec = Time.now - File.mtime(abs)
        format_age(age_sec)
      end

      def format_age(sec)
        if sec < 3600
          format("%.0fm ago", sec / 60.0)
        elsif sec < 86_400
          format("%.1fh ago", sec / 3600.0)
        else
          format("%.1fd ago", sec / 86_400.0)
        end
      end

      def format_percent(ratio)
        format("%.1f%%", ratio * 100.0)
      end
    end
  end
end
