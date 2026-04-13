require "cgi"
require "pathname"

module Polyrun
  module Coverage
    module Merge
      module_function

      def to_simplecov_json(coverage_blob, meta: {}, groups: nil, strip_internal_meta: true)
        m = meta.is_a?(Hash) ? meta : {}
        meta_out = {}
        m.each { |k, v| meta_out[k.to_s] = v }
        if strip_internal_meta
          INTERNAL_META_KEYS.each { |k| meta_out.delete(k) }
        end
        meta_out["simplecov_version"] ||= Polyrun::VERSION
        g =
          if groups.nil?
            {}
          else
            stringify_keys_deep(groups)
          end
        {
          "meta" => meta_out,
          "coverage" => stringify_keys_deep(coverage_blob),
          "groups" => g
        }
      end

      def stringify_keys_deep(obj)
        case obj
        when Hash
          obj.each_with_object({}) { |(k, v), h| h[k.to_s] = stringify_keys_deep(v) }
        when Array
          obj.map { |e| stringify_keys_deep(e) }
        else
          obj
        end
      end

      def emit_lcov(coverage_blob)
        lines = []
        coverage_blob.each do |path, file|
          phys = path.to_s
          lines << "TN:polyrun"
          lines << "SF:#{phys}"
          line_arr = line_array_from_file_entry(file)
          next unless line_arr.is_a?(Array)

          line_arr.each_with_index do |hit, i|
            next if hit.nil? || hit == "ignored"

            n = hit.to_i
            lines << "DA:#{i + 1},#{n}" if n >= 0
          end
          lines << "end_of_record"
        end
        lines.join("\n") + "\n"
      end

      # Cobertura XML (no extra gems). Root metrics match common consumers (spec3.md).
      # When +root+ is set, +filename+ on each +class+ is relative to that directory (for tools that expect +lib/...+).
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- linear XML assembly
      def emit_cobertura(coverage_blob, root: nil)
        lines_valid = 0
        lines_covered = 0
        coverage_blob.each_value do |file|
          line_arr = line_array_from_file_entry(file)
          next unless line_arr.is_a?(Array)

          line_arr.each do |hit|
            next if hit.nil? || hit == "ignored"

            lines_valid += 1
            lines_covered += 1 if hit.to_i > 0
          end
        end
        line_rate = lines_valid.positive? ? (lines_covered.to_f / lines_valid) : 0.0
        ts = Time.now.to_i

        lines = []
        lines << '<?xml version="1.0" encoding="UTF-8"?>'
        lines << '<!DOCTYPE coverage SYSTEM "http://cobertura.sourceforge.net/xml/coverage-04.dtd">'
        lines << %(<coverage line-rate="#{line_rate}" branch-rate="0" lines-covered="#{lines_covered}" lines-valid="#{lines_valid}" branches-covered="0" branches-valid="0" complexity="0" timestamp="#{ts}" version="1">)
        lines << '<packages><package name="app"><classes>'
        coverage_blob.each do |path, file|
          line_arr = line_array_from_file_entry(file)
          next unless line_arr.is_a?(Array)

          fname = CGI.escapeHTML(cobertura_display_path(path, root)).gsub("'", "&#39;")
          lines << %(<class name="#{fname}" filename="#{fname}"><lines>)
          line_arr.each_with_index do |hit, i|
            next if hit.nil? || hit == "ignored"

            n = hit.to_i
            lines << %(<line number="#{i + 1}" hits="#{n}"/>)
          end
          lines << "</lines></class>"
        end
        lines << "</classes></package></packages></coverage>\n"
        lines.join
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      def cobertura_display_path(path, root)
        p = path.to_s
        return p if root.nil? || root.to_s.empty?

        abs = File.expand_path(p)
        r = File.expand_path(root.to_s)
        Pathname.new(abs).relative_path_from(Pathname.new(r)).to_s
      rescue ArgumentError
        abs
      end

      # Aggregate stats for a SimpleCov-compatible coverage blob (lines arrays only).
      def console_summary(coverage_blob)
        files = 0
        relevant = 0
        covered = 0
        coverage_blob.each_value do |file|
          line_arr = line_array_from_file_entry(file)
          next unless line_arr.is_a?(Array)

          files += 1
          line_arr.each do |h|
            next if h.nil? || h == "ignored"

            relevant += 1
            covered += 1 if h.to_i > 0
          end
        end
        pct = relevant.positive? ? (100.0 * covered / relevant) : 0.0
        {
          files: files,
          lines_relevant: relevant,
          lines_covered: covered,
          line_percent: pct
        }
      end

      def format_console_summary(summary)
        s = summary.is_a?(Hash) ? summary : console_summary(summary)
        format(
          "Polyrun coverage summary: %.2f%% lines (%d / %d) across %d files\n",
          s[:line_percent] || s["line_percent"],
          s[:lines_covered] || s["lines_covered"],
          s[:lines_relevant] || s["lines_relevant"],
          s[:files] || s["files"]
        )
      end

      # Per-file line stats for HTML and other formatters.
      # Integer line counts for one file entry (for O(files x groups) group aggregation).
      def line_counts(file_entry)
        line_arr = line_array_from_file_entry(file_entry)
        return {relevant: 0, covered: 0} unless line_arr.is_a?(Array)

        relevant = 0
        covered = 0
        line_arr.each do |h|
          next if h.nil? || h == "ignored"

          relevant += 1
          covered += 1 if h.to_i > 0
        end
        {relevant: relevant, covered: covered}
      end

      def file_line_stats(file)
        c = line_counts(file)
        rel = c[:relevant]
        cov = c[:covered]
        pct = rel.positive? ? (100.0 * cov / rel) : 0.0
        [pct, rel, cov]
      end
    end
  end
end

require_relative "formatters_html"
