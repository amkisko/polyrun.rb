module Polyrun
  module Export
    # RFC-style CSV field escaping for report exports.
    module Csv
      module_function

      def escape_field(value)
        string = value.nil? ? "" : value.to_s
        if string.match?(/[",\r\n]/)
          "\"#{string.gsub('"', '""')}\""
        else
          string
        end
      end

      def generate(headers, rows)
        lines = [headers.map { |header| escape_field(header) }.join(",")]
        rows.each do |row|
          lines << Array(row).map { |cell| escape_field(cell) }.join(",")
        end
        lines.join("\n") + "\n"
      end
    end
  end
end
