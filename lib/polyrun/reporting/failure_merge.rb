require "json"
require "fileutils"

require_relative "../export/csv"
require_relative "../export/markdown"

module Polyrun
  module Reporting
    # Merge per-worker / per-shard failure fragments (JSONL or RSpec JSON) into one report.
    # Fragment basenames align with {Coverage::CollectorFragmentMeta} (worker index and optional matrix shard).
    module FailureMerge
      DEFAULT_FRAGMENT_DIR = "tmp/polyrun_failures".freeze
      FRAGMENT_GLOB = "polyrun-failure-fragment-*.jsonl".freeze
      CSV_HEADERS = %w[
        id full_description location file_path line_number message exception_class
        polyrun_shard_index polyrun_shard_total source
      ].freeze

      module_function

      def default_fragment_glob(dir = nil)
        root = File.expand_path(dir || DEFAULT_FRAGMENT_DIR, Dir.pwd)
        File.join(root, FRAGMENT_GLOB)
      end

      def merge_fragment_paths(quiet: false)
        p = default_fragment_glob
        Dir.glob(p).sort.tap do |paths|
          Polyrun::Log.warn "merge-failures: no files matched #{p}" if paths.empty? && !quiet
        end
      end

      # @param paths [Array<String>] fragment paths (.jsonl and/or RSpec --format json outputs)
      # @param format [String] "jsonl", "json", "csv", or "markdown"
      # @param output [String] destination path
      # @return [Integer] count of failure rows merged
      def merge_files!(paths, output:, format: "jsonl")
        fmt = format.to_s.downcase
        rows = collect_rows(paths)
        out_abs = File.expand_path(output)
        FileUtils.mkdir_p(File.dirname(out_abs))
        case fmt
        when "json"
          write_json_output!(out_abs, paths, rows)
        when "jsonl"
          write_jsonl_output!(out_abs, rows)
        when "csv"
          write_csv_output!(out_abs, rows)
        when "markdown", "md"
          write_markdown_output!(out_abs, rows)
        else
          raise Polyrun::Error, "merge-failures: unknown format #{fmt.inspect} (use jsonl, json, csv, or markdown)"
        end
        rows.size
      end

      def write_json_output!(out_abs, paths, rows)
        doc = {
          "meta" => {
            "polyrun_merge" => true,
            "inputs" => paths.map { |p| File.expand_path(p) },
            "failure_count" => rows.size
          },
          "failures" => rows
        }
        File.write(out_abs, JSON.generate(doc))
      end

      def write_jsonl_output!(out_abs, rows)
        File.write(out_abs, rows.map { |h| JSON.generate(h) }.join("\n") + (rows.empty? ? "" : "\n"))
      end

      def write_csv_output!(out_abs, rows)
        csv_rows = rows.map { |row| CSV_HEADERS.map { |key| row[key] } }
        File.write(out_abs, Export::Csv.generate(CSV_HEADERS, csv_rows))
      end

      def write_markdown_output!(out_abs, rows)
        sections = rows.map.with_index(1) do |row, index|
          {
            heading: "Failure #{index}: #{row["full_description"] || row["location"] || row["id"]}",
            headers: %w[field value],
            rows: row.sort_by { |key, _| key.to_s }.map { |key, value| [key, value] }
          }
        end
        sections = [{heading: "Failures", body: "(none)"}] if sections.empty?
        File.write(out_abs, Export::Markdown.document("Polyrun failure report", sections))
      end

      def collect_rows(paths)
        rows = []
        paths.each do |p|
          rows.concat(rows_from_path(p))
        end
        rows
      end

      def rows_from_path(path)
        ext = File.extname(path).downcase
        if ext == ".jsonl"
          return rows_from_jsonl_file(path)
        end

        text = File.read(path)
        data =
          begin
            JSON.parse(text)
          rescue JSON::ParserError => e
            raise Polyrun::Error, "merge-failures: #{path} is not valid JSON: #{e.message}"
          end
        if data.is_a?(Hash) && data["examples"].is_a?(Array)
          return failures_from_rspec_examples(data["examples"])
        end

        hint =
          if data.is_a?(Hash)
            keys = data.keys
            "got JSON object with keys: #{keys.take(12).join(", ")}" + ((keys.size > 12) ? ", …" : "")
          else
            "got #{data.class}"
          end
        raise Polyrun::Error,
          "merge-failures: #{path} is not RSpec JSON (expected top-level \"examples\" array). #{hint}. " \
          "Use RSpec --format json, or polyrun failure JSONL (.jsonl fragments)."
      end

      def rows_from_jsonl_file(path)
        acc = []
        File.readlines(path, chomp: true).each_with_index do |line, idx|
          line = line.strip
          next if line.empty?

          acc << parse_jsonl_line!(path, idx + 1, line)
        end
        acc
      end

      def parse_jsonl_line!(path, line_number, line)
        JSON.parse(line)
      rescue JSON::ParserError => e
        raise Polyrun::Error,
          "merge-failures: invalid JSONL at #{path} line #{line_number}: #{e.message}"
      end

      def failures_from_rspec_examples(examples)
        examples.each_with_object([]) do |ex, acc|
          next unless ex.is_a?(Hash)
          next unless ex["status"].to_s == "failed"

          acc << rspec_example_to_row(ex)
        end
      end

      def rspec_example_to_row(ex)
        ex = ex.transform_keys(&:to_s)
        exc = ex["exception"] || {}
        exc = exc.transform_keys(&:to_s) if exc.is_a?(Hash)
        {
          "id" => ex["id"],
          "full_description" => ex["full_description"],
          "location" => (ex["file_path"] && ex["line_number"]) ? "#{ex["file_path"]}:#{ex["line_number"]}" : ex["full_description"],
          "file_path" => ex["file_path"],
          "line_number" => ex["line_number"],
          "message" => exc["message"] || ex["full_description"],
          "exception_class" => exc["class"],
          "source" => "rspec_json"
        }.compact
      end
    end
  end
end
