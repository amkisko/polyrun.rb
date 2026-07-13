require "json"
require "optparse"

module Polyrun
  class CLI
    module ReportCommands
      private

      def cmd_report_junit(argv)
        inputs, output, report_format = report_junit_parse_inputs(argv)
        inputs.uniq!
        if inputs.empty?
          Polyrun::Log.warn "report-junit: need -i FILE (existing path after glob expansion)"
          return 2
        end

        inputs = inputs.map { |p| File.expand_path(p) }
        return 2 unless report_junit_inputs_exist?(inputs)

        out = report_junit_resolved_output(inputs, output, report_format)
        path =
          if inputs.size == 1
            Polyrun::Reporting::Junit.write_from_json_file(inputs.first, output_path: out, format: report_format)
          else
            Polyrun::Reporting::Junit.merge_rspec_json_files(inputs, output_path: out, format: report_format)
          end
        Polyrun::Log.puts path
        0
      end

      def report_junit_parse_inputs(argv)
        inputs = []
        output = nil
        report_format = "xml"
        OptionParser.new do |opts|
          opts.banner = "usage: polyrun report-junit -i FILE [-i FILE]... [-o PATH] [--format xml|csv|markdown]"
          opts.on("-i", "--input PATH", "RSpec JSON (repeatable; globs ok; multiple files merge examples)") do |v|
            expand_merge_input_pattern(v).each { |x| inputs << x }
          end
          opts.on("-o", "--output PATH", "Default: <dir of first input>/junit.<ext>") { |v| output = v }
          opts.on("--format VAL", "xml (default), csv, or markdown") { |v| report_format = v }
        end.parse!(argv)
        if inputs.empty? && argv.first
          expand_merge_input_pattern(argv.first).each { |x| inputs << x }
        end
        [inputs, output, report_format]
      end

      def report_junit_inputs_exist?(inputs)
        inputs.each do |p|
          unless File.file?(p)
            Polyrun::Log.warn "report-junit: not a file: #{p}"
            return false
          end
        end
        true
      end

      def report_junit_resolved_output(inputs, output, format)
        if output
          File.expand_path(output)
        else
          extension = case format.to_s.downcase
          when "csv" then "csv"
          when "markdown", "md" then "md"
          else "xml"
          end
          File.join(File.dirname(inputs.first), "junit.#{extension}")
        end
      end

      def cmd_report_timing(argv)
        input = nil
        out_file = nil
        top = 30
        report_format = "text"
        OptionParser.new do |opts|
          opts.banner = "usage: polyrun report-timing -i FILE [-o PATH] [--top N] [--format text|csv|markdown]"
          opts.on("-i", "--input PATH", "Merged polyrun_timing.json (path => seconds)") { |v| input = v }
          opts.on("-o", "--output PATH", "Write summary to file instead of stdout") { |v| out_file = v }
          opts.on("--top N", Integer) { |v| top = v }
          opts.on("--format VAL", "text (default), csv, or markdown") { |v| report_format = v }
        end.parse!(argv)
        input ||= argv.first

        unless input && File.file?(input)
          Polyrun::Log.warn "report-timing: need -i FILE"
          return 2
        end

        merged = JSON.parse(File.read(File.expand_path(input)))
        begin
          text = Polyrun::Timing::Summary.render(merged, format: report_format, top: top)
        rescue Polyrun::Error => e
          Polyrun::Log.warn e.message.to_s
          return 2
        end
        if out_file
          File.write(File.expand_path(out_file), text)
          Polyrun::Log.puts File.expand_path(out_file)
        else
          Polyrun::Log.print text
        end
        0
      end
    end
  end
end
