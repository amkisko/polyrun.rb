module Polyrun
  module Export
    # GitHub-flavored markdown tables for report exports.
    module Markdown
      module_function

      def escape_cell(value)
        value.nil? ? "" : value.to_s.gsub("|", "\\|").tr("\n", " ")
      end

      def heading(level, text)
        level = level.to_i.clamp(1, 6)
        "#{"#" * level} #{text}\n"
      end

      def table(headers, rows)
        return "" if headers.nil? || headers.empty?

        header_line = "| #{headers.map { |header| escape_cell(header) }.join(" | ")} |"
        separator_line = "| #{headers.map { "---" }.join(" | ")} |"
        body_lines = rows.map do |row|
          "| #{Array(row).map { |cell| escape_cell(cell) }.join(" | ")} |"
        end
        ([header_line, separator_line] + body_lines).join("\n") + "\n"
      end

      def document(title, sections)
        lines = [heading(1, title), ""]
        sections.each do |section|
          heading_text = section[:heading] || section["heading"]
          lines << heading(2, heading_text) if heading_text && !heading_text.to_s.empty?

          body = section[:body] || section["body"]
          lines << body if body && !body.to_s.empty?

          table_headers = section[:headers] || section["headers"]
          table_rows = section[:rows] || section["rows"]
          if table_headers && !table_headers.empty?
            lines << table(table_headers, table_rows || [])
          end
          lines << ""
        end
        lines.join("\n")
      end
    end
  end
end
