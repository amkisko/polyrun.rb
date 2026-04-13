require "cgi"

module Polyrun
  module Coverage
    module Merge
      module_function

      # Minimal standalone HTML report (no extra gems), index listing similar to SimpleCov.
      def emit_html(coverage_blob, title: "Polyrun coverage")
        summary = console_summary(coverage_blob)
        rows = []
        coverage_blob.keys.sort.each do |path|
          file = coverage_blob[path]
          pct, rel, cov = file_line_stats(file)
          esc = CGI.escapeHTML(path.to_s)
          rows << "<tr><td class=\"path\">#{esc}</td><td class=\"pct\">#{format("%.2f", pct)}</td><td class=\"hits\">#{cov} / #{rel}</td></tr>"
        end
        esc_title = CGI.escapeHTML(title.to_s)
        <<~HTML
          <!DOCTYPE html>
          <html lang="en">
          <head>
            <meta charset="utf-8"/>
            <title>#{esc_title}</title>
            <style>
              body { font-family: system-ui, sans-serif; margin: 1.5rem; color: #1a1a1a; }
              h1 { font-size: 1.25rem; }
              .summary { margin: 1rem 0; }
              table { border-collapse: collapse; width: 100%; max-width: 56rem; }
              th, td { border: 1px solid #ccc; padding: 0.35rem 0.5rem; text-align: left; }
              th { background: #f4f4f4; }
              tr:nth-child(even) { background: #fafafa; }
              td.path { word-break: break-all; font-size: 0.9rem; }
              td.pct { white-space: nowrap; }
            </style>
          </head>
          <body>
            <h1>#{esc_title}</h1>
            <p class="summary">
              <strong>#{format("%.2f", summary[:line_percent])}%</strong> lines
              (#{summary[:lines_covered]} / #{summary[:lines_relevant]}) across #{summary[:files]} files
            </p>
            <table>
              <thead><tr><th>File</th><th>Coverage</th><th>Lines (covered / relevant)</th></tr></thead>
              <tbody>
              #{rows.join("\n")}
              </tbody>
            </table>
          </body>
          </html>
        HTML
      end
    end
  end
end
