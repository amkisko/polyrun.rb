require "json"

require_relative "../export/csv"
require_relative "../export/markdown"

module Polyrun
  module Benchmark
    # Formats benchmark profile JSON for humans and downstream tools.
    module Report
      METRIC_HEADERS = %w[section name value unit].freeze
      LINE_HEADERS = %w[index text].freeze

      module_function

      def load(path)
        ext = File.extname(path).downcase
        if ext == ".json"
          JSON.parse(File.read(path))
        else
          {"meta" => {}, "lines" => File.read(path).lines.map(&:chomp), "metrics" => []}
        end
      end

      def render(data, format: "text")
        case format.to_s.downcase
        when "text", "console", "txt" then format_text(data)
        when "json" then JSON.pretty_generate(data)
        when "csv" then format_csv(data)
        when "markdown", "md" then format_markdown(data)
        else
          raise Polyrun::Error, "report-benchmark: unknown format #{format.inspect} (use text, json, csv, or markdown)"
        end
      end

      def format_text(data)
        meta = data["meta"] || {}
        header = [
          "Benchmark profile",
          "commit: #{meta["commit"]}",
          "recorded_at: #{meta["recorded_at"]}",
          "ruby: #{meta["ruby"]}",
          ""
        ]
        (header + Array(data["lines"])).join("\n") + "\n"
      end

      def format_csv(data)
        metrics = Array(data["metrics"])
        if metrics.any?
          rows = metrics.map { |metric| [metric["section"], metric["name"], metric["value"], metric["unit"]] }
          return Export::Csv.generate(METRIC_HEADERS, rows)
        end

        rows = Array(data["lines"]).each_with_index.map { |line, index| [index + 1, line] }
        Export::Csv.generate(LINE_HEADERS, rows)
      end

      def format_markdown(data)
        meta = data["meta"] || {}
        sections = [
          {
            heading: "Metadata",
            headers: %w[key value],
            rows: meta.sort_by { |key, _| key.to_s }
          }
        ]

        metrics = Array(data["metrics"])
        if metrics.any?
          sections << {
            heading: "Metrics",
            headers: METRIC_HEADERS,
            rows: metrics.map { |metric| [metric["section"], metric["name"], metric["value"], metric["unit"]] }
          }
        end

        line_rows = Array(data["lines"]).reject(&:empty?).zip
        sections << {
          heading: "Log",
          headers: %w[line],
          rows: line_rows.empty? ? [["(empty)"]] : line_rows
        }
        Export::Markdown.document("Polyrun benchmark profile", sections)
      end
    end
  end
end
