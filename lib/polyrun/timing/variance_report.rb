module Polyrun
  module Timing
    # Flags high-variance, flaky, and regression timing entries.
    module VarianceReport
      module_function

      def analyze(merged_stats)
        flags = []
        merged_stats.each do |path, entry|
          h = Stats.normalize_entry(entry)
          next if h["runs"] < 2

          median = h["mean"]
          if median.positive? && (h["p95"] / median) > 2.0
            flags << {path: path, kind: "high_variance", detail: "p95/mean=#{format('%.2f', h["p95"] / median)}"}
          end

          if h["runs"] >= 3 && (h["failures"].to_f / h["runs"]) > 0.3
            flags << {path: path, kind: "often_failed", detail: "failures=#{h["failures"]}/#{h["runs"]}"}
          end

          if h["timeouts"].to_i >= 2
            flags << {path: path, kind: "timeout_cluster", detail: "timeouts=#{h["timeouts"]}"}
          end

          if h["mean"].positive? && h["last_seconds"] > (2.0 * h["mean"])
            flags << {path: path, kind: "runtime_regression", detail: "last=#{h["last_seconds"]} mean=#{h["mean"]}"}
          end
        end
        flags
      end

      def emit_warnings!(merged_stats)
        analyze(merged_stats).each do |f|
          Polyrun::Log.warn "polyrun timing #{f[:kind]}: #{f[:path]} (#{f[:detail]})"
        end
      end

      def format_report(merged_stats)
        lines = ["Polyrun timing variance report", ""]
        analyze(merged_stats).each do |f|
          lines << "  [#{f[:kind]}] #{f[:path]} — #{f[:detail]}"
        end
        lines << "  (none)" if lines.size == 2
        lines.join("\n") + "\n"
      end
    end
  end
end
