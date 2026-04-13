module Polyrun
  module Coverage
    # Lists Cobertura +line+ elements with +hits="0"+ (optional dev aid). Set +SHOW_ZERO_COVERAGE=1+ and run
    # after Cobertura XML exists (e.g. after {Collector} with Cobertura formatter).
    # Uses a small string scan (no REXML) so the gem stays stdlib-only everywhere REXML may be omitted.
    module CoberturaZeroLines
      module_function

      def run(xml_path:, filename_prefix: "lib/")
        return unless ENV["SHOW_ZERO_COVERAGE"] == "1"
        return unless File.file?(xml_path)

        uncovered = extract(File.read(xml_path), filename_prefix: filename_prefix)
        uncovered.sort_by { |e| [e[:file], e[:line]] }.each do |line_info|
          Polyrun::Log.puts "#{line_info[:file]}:#{line_info[:line]}"
        end
      end

      def extract(xml_text, filename_prefix: "lib/")
        uncovered = []
        xml_text.scan(/<class[^>]+filename="([^"]+)"[^>]*>(.*?)<\/class>/m) do |filename, class_body|
          next unless filename.start_with?(filename_prefix)

          class_body.scan(/<line number="(\d+)" hits="(\d+)"/) do |num_s, hits_s|
            uncovered << {file: filename, line: num_s.to_i} if hits_s.to_i == 0
          end
        end
        uncovered
      end
    end
  end
end
