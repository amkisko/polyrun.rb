require "json"

require_relative "../export/csv"
require_relative "../export/markdown"

module Polyrun
  module Reporting
    module Junit
      CSV_HEADERS = %w[classname name status time_seconds failure_message].freeze
      MARKDOWN_HEADERS = %w[classname name status time_seconds].freeze

      module_function

      def render(doc, format: "xml")
        case format.to_s.downcase
        when "xml" then emit_xml(doc)
        when "csv" then emit_csv(doc)
        when "markdown", "md" then emit_markdown(doc)
        else
          raise Polyrun::Error, "report-junit: unknown format #{format.inspect} (use xml, csv, or markdown)"
        end
      end

      def emit_csv(doc)
        rows = Array(doc["testcases"]).map { |testcase| csv_row(testcase) }
        Export::Csv.generate(CSV_HEADERS, rows)
      end

      def csv_row(testcase)
        testcase = testcase.transform_keys(&:to_s)
        failure = testcase["failure"] || {}
        failure = failure.transform_keys(&:to_s) if failure.is_a?(Hash)
        [
          testcase["classname"],
          testcase["name"],
          status_of(testcase),
          format_float(testcase["time"] || 0),
          failure["message"]
        ]
      end

      def emit_markdown(doc)
        cases = Array(doc["testcases"])
        total_time = cases.sum { |testcase| (testcase["time"] || testcase[:time] || 0).to_f }
        failures = cases.count { |testcase| status_of(testcase) == "failed" }
        errors = cases.count { |testcase| status_of(testcase) == "error" }
        skipped = cases.count { |testcase| %w[pending skipped].include?(status_of(testcase)) }
        summary_rows = [
          ["tests", cases.size],
          ["failures", failures],
          ["errors", errors],
          ["skipped", skipped],
          ["time_seconds", format_float(total_time)],
          ["hostname", doc["hostname"]]
        ]
        testcase_rows = cases.map do |testcase|
          testcase = testcase.transform_keys(&:to_s)
          [testcase["classname"], testcase["name"], status_of(testcase), format_float(testcase["time"] || 0)]
        end
        sections = [
          {heading: "Summary", headers: %w[metric value], rows: summary_rows},
          {heading: "Test cases", headers: MARKDOWN_HEADERS, rows: testcase_rows}
        ]
        failed = cases.select { |testcase| %w[failed error].include?(status_of(testcase)) }
        unless failed.empty?
          failure_rows = failed.map do |testcase|
            testcase = testcase.transform_keys(&:to_s)
            failure = (testcase["failure"] || {}).transform_keys(&:to_s)
            [testcase["name"], status_of(testcase), failure["message"], failure["body"]]
          end
          sections << {
            heading: "Failures",
            headers: %w[name status message body],
            rows: failure_rows
          }
        end
        Export::Markdown.document(doc["name"].to_s, sections)
      end
    end
  end
end
