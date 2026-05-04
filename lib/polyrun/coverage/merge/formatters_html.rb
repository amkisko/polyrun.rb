# rubocop:disable Polyrun/FileLength -- HTML merge formatter + helpers in one file
require "cgi"
require "digest/sha1"
require "erb"
require "pathname"

module Polyrun
  module Coverage
    module Merge
      module_function

      # Standalone HTML report with summary, file table, and per-file source details.
      # rubocop:disable Metrics/AbcSize -- linear assembly of overview, file table, sections, asset reads
      def emit_html(coverage_blob, title: "Polyrun coverage", root: nil, groups: nil, generated_at: Time.now)
        files = coverage_blob.keys.sort.map { |path| html_file_payload(path, coverage_blob[path], root) }
        summary = html_summary(files)
        groups_html = render_html_partial("groups_table", group_rows_html: html_group_rows(groups).join("\n"))
        overview_html = render_html_partial(
          "overview",
          summary: summary,
          summary_badge_class: html_badge_class(summary[:line_percent]),
          groups_html: groups_html
        )
        file_list_html = render_html_partial("file_list", file_rows_html: files.map { |file| html_file_list_row(file) }.join("\n"))
        file_sections_html = files.map { |file| render_html_partial("file_section", file: file) }.join("\n")
        ERB.new(File.read(html_template_path), trim_mode: "-").result_with_hash(
          title: CGI.escapeHTML(title.to_s),
          generated_label: html_generated_label(generated_at),
          overview_html: overview_html,
          file_list_html: file_list_html,
          file_sections_html: file_sections_html,
          stylesheet: File.read(html_stylesheet_path),
          javascript: File.read(html_javascript_path)
        )
      end
      # rubocop:enable Metrics/AbcSize

      def html_asset_dir
        File.join(__dir__, "html")
      end

      def html_template_path
        File.join(html_asset_dir, "template.html.erb")
      end

      def html_stylesheet_path
        File.join(html_asset_dir, "report.css")
      end

      def html_javascript_path
        File.join(html_asset_dir, "report.js")
      end

      def html_partial_path(name)
        File.join(html_asset_dir, "_#{name}.html.erb")
      end

      def render_html_partial(name, locals = {})
        ERB.new(File.read(html_partial_path(name)), trim_mode: "-").result_with_hash(locals)
      end

      def html_file_payload(path, file, root)
        line_arr = line_array_from_file_entry(file) || []
        source_lines = html_source_lines(path, line_arr.length)
        counts = line_counts(file)
        relevant = counts[:relevant]
        covered = counts[:covered]
        total_hits = line_arr.sum { |hit| html_numeric_hit(hit) || 0 }
        pct = relevant.positive? ? (100.0 * covered / relevant) : 0.0
        {
          id: "file-#{Digest::SHA1.hexdigest(path.to_s)}",
          path: path.to_s,
          display_path: html_display_path(path, root),
          badge_class: html_badge_class(pct),
          total_lines: [source_lines.length, line_arr.length].max,
          relevant: relevant,
          covered: covered,
          missed: relevant - covered,
          avg_hits: relevant.positive? ? (total_hits.to_f / relevant) : 0.0,
          line_percent: pct,
          source_rows: html_source_rows(source_lines, line_arr)
        }
      end

      def html_summary(files)
        relevant = files.sum { |file| file[:relevant] }
        covered = files.sum { |file| file[:covered] }
        total_hits = files.sum { |file| file[:avg_hits] * file[:relevant] }
        {
          files: files.length,
          lines_relevant: relevant,
          lines_covered: covered,
          lines_missed: relevant - covered,
          line_percent: relevant.positive? ? (100.0 * covered / relevant) : 0.0,
          avg_hits: relevant.positive? ? (total_hits.to_f / relevant) : 0.0
        }
      end

      def html_group_rows(groups)
        return [] unless groups.is_a?(Hash) && !groups.empty?

        groups.map do |name, data|
          pct = html_group_percent(data)
          <<~ROW.strip
            <tr>
              <td>#{CGI.escapeHTML(name.to_s)}</td>
              <td class="cell--number"><span class="badge #{html_badge_class(pct)}">#{format("%.2f", pct)}%</span></td>
            </tr>
          ROW
        end
      end

      def html_group_percent(data)
        return 0.0 unless data.is_a?(Hash)

        lines = data["lines"] || data[:lines]
        pct = lines.is_a?(Hash) ? (lines["covered_percent"] || lines[:covered_percent]) : nil
        pct.to_f
      end

      def html_file_list_row(file)
        <<~ROW.strip
          <tr class="t-file">
            <td class="strong t-file__name"><a href="##{file[:id]}" class="src_link" title="#{CGI.escapeHTML(file[:display_path])}">#{CGI.escapeHTML(file[:display_path])}</a></td>
            <td class="cell--number"><span class="badge #{html_badge_class(file[:line_percent])}">#{format("%.2f", file[:line_percent])}%</span></td>
            <td class="cell--number">#{file[:total_lines]}</td>
            <td class="cell--number">#{file[:relevant]}</td>
            <td class="cell--number">#{file[:covered]}</td>
            <td class="cell--number">#{file[:missed]}</td>
            <td class="cell--number">#{format("%.2f", file[:avg_hits])}</td>
          </tr>
        ROW
      end

      def html_source_rows(source_lines, line_arr)
        max_len = [source_lines.length, line_arr.length].max
        Array.new(max_len) do |idx|
          source = source_lines[idx] || ""
          hit = line_arr[idx]
          css = html_line_class(hit)
          hits_label = html_hit_label(hit)
          <<~ROW.strip
            <tr class="#{css}">
              <td class="line-num">#{idx + 1}</td>
              <td class="line-hits">#{hits_label}</td>
              <td class="line-source"><code>#{source.empty? ? "&nbsp;" : CGI.escapeHTML(source)}</code></td>
            </tr>
          ROW
        end
      end

      def html_source_lines(path, fallback_length)
        return Array.new(fallback_length, "") unless File.file?(path.to_s)

        File.readlines(path.to_s, chomp: true)
      rescue Errno::ENOENT, Errno::EACCES, ArgumentError
        Array.new(fallback_length, "")
      end

      def html_display_path(path, root)
        p = File.expand_path(path.to_s)
        return p if root.nil? || root.to_s.empty?

        Pathname.new(p).relative_path_from(Pathname.new(File.expand_path(root.to_s))).to_s
      rescue ArgumentError
        p
      end

      def html_generated_label(generated_at)
        t = generated_at.is_a?(Time) ? generated_at : Time.now
        t.utc.strftime("%Y-%m-%d %H:%M:%S UTC")
      end

      def html_badge_class(percent)
        return "green" if percent >= 90.0
        return "yellow" if percent >= 80.0

        "red"
      end

      def html_numeric_hit(hit)
        return nil if hit.nil? || hit == "ignored"

        hit.to_i
      end

      def html_hit_label(hit)
        return "" if hit.nil?
        return "ignored" if hit == "ignored"

        hit.to_i.to_s
      end

      def html_line_class(hit)
        return "line-none" if hit.nil?
        return "line-ignored" if hit == "ignored"

        hit.to_i.positive? ? "line-covered" : "line-missed"
      end
    end
  end
end
# rubocop:enable Polyrun/FileLength
