require_relative "stats"
require_relative "../export/csv"
require_relative "../export/markdown"

module Polyrun
  module Timing
    # Human-readable slow-file list from merged timing JSON (per-file cost).
    module Summary
      CSV_HEADERS = %w[rank path last_seconds min max mean p95 runs failures timeouts].freeze
      MARKDOWN_HEADERS = %w[rank path seconds].freeze

      module_function

      def ranked_entries(merged, top: 30)
        return [] if merged.nil? || merged.empty?

        merged.map { |path, entry| [path, Stats.normalize_entry(entry)] }
          .sort_by { |(_, entry)| -Stats.binpack_weight(entry) }
          .first(Integer(top))
      end

      # +merged+ is path (String) => seconds (Float) or stats Hash, as produced by +Timing::Merge.merge_files+.
      def format_slow_files(merged, top: 30, title: "Polyrun slowest files (by wall time, seconds)")
        return "#{title}\n  (no data)\n" if merged.nil? || merged.empty?

        lines = [title, ""]
        ranked_entries(merged, top: top).each_with_index do |(path, entry), index|
          lines << format("  %2d. %s  %.4f", index + 1, path, Stats.binpack_weight(entry).to_f)
        end
        lines.join("\n") + "\n"
      end

      def format_csv(merged, top: 30)
        rows = ranked_entries(merged, top: top).each_with_index.map do |(path, entry), index|
          [
            index + 1,
            path,
            entry["last_seconds"],
            entry["min"],
            entry["max"],
            entry["mean"],
            entry["p95"],
            entry["runs"],
            entry["failures"],
            entry["timeouts"]
          ]
        end
        Export::Csv.generate(CSV_HEADERS, rows)
      end

      def format_markdown(merged, top: 30, title: "Polyrun slowest files")
        rows = ranked_entries(merged, top: top).each_with_index.map do |(path, entry), index|
          [index + 1, path, format("%.4f", Stats.binpack_weight(entry).to_f)]
        end
        Export::Markdown.document(
          title,
          [{heading: "Slow files", headers: MARKDOWN_HEADERS, rows: rows}]
        )
      end

      def render(merged, format: "text", **kwargs)
        case format.to_s.downcase
        when "text", "console", "txt" then format_slow_files(merged, **kwargs)
        when "csv" then format_csv(merged, **kwargs)
        when "markdown", "md" then format_markdown(merged, **kwargs)
        else
          raise Polyrun::Error, "report-timing: unknown format #{format.inspect} (use text, csv, or markdown)"
        end
      end

      def write_file(merged, path, **kwargs)
        format = kwargs.delete(:format) || "text"
        File.write(path, render(merged, format: format, **kwargs))
        path
      end
    end
  end
end
