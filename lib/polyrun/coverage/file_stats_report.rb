require_relative "../export/csv"
require_relative "../export/markdown"

module Polyrun
  module Coverage
    # Per-file line coverage tables for CSV and Markdown exports.
    module FileStatsReport
      HEADERS = %w[path line_percent lines_covered lines_relevant].freeze

      module_function

      def file_rows(coverage_blob)
        coverage_blob.map do |path, file_entry|
          line_percent, lines_relevant, lines_covered = Merge.file_line_stats(file_entry)
          [path, format("%.2f", line_percent), lines_covered, lines_relevant]
        end.sort_by { |row| row[1].to_f }
      end

      def emit_csv(coverage_blob)
        Export::Csv.generate(HEADERS, file_rows(coverage_blob))
      end

      def emit_markdown(coverage_blob, title: "Polyrun coverage report")
        summary = Merge.console_summary(coverage_blob)
        summary_line = Merge.format_console_summary(summary).strip
        Export::Markdown.document(
          title,
          [
            {body: summary_line},
            {heading: "Per-file coverage", headers: HEADERS, rows: file_rows(coverage_blob)}
          ]
        )
      end
    end
  end
end
