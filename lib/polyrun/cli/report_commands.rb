require "json"
require "optparse"

module Polyrun
  class CLI
    module ReportCommands
      private

      def cmd_report_junit(argv)
        inputs = []
        output = nil
        parser = OptionParser.new do |opts|
          opts.banner = "usage: polyrun report-junit -i FILE [-i FILE]... [-o PATH]"
          opts.on("-i", "--input PATH", "RSpec JSON (repeatable; globs ok; multiple files merge examples)") do |v|
            expand_merge_input_pattern(v).each { |x| inputs << x }
          end
          opts.on("-o", "--output PATH", "Default: <dir of first input>/junit.xml") { |v| output = v }
        end
        parser.parse!(argv)
        if inputs.empty? && argv.first
          expand_merge_input_pattern(argv.first).each { |x| inputs << x }
        end

        inputs.uniq!
        if inputs.empty?
          Polyrun::Log.warn "report-junit: need -i FILE (existing path after glob expansion)"
          return 2
        end

        inputs = inputs.map { |p| File.expand_path(p) }
        inputs.each do |p|
          unless File.file?(p)
            Polyrun::Log.warn "report-junit: not a file: #{p}"
            return 2
          end
        end

        out =
          if output
            File.expand_path(output)
          else
            File.join(File.dirname(inputs.first), "junit.xml")
          end

        path =
          if inputs.size == 1
            Polyrun::Reporting::Junit.write_from_json_file(inputs.first, output_path: out)
          else
            Polyrun::Reporting::Junit.merge_rspec_json_files(inputs, output_path: out)
          end
        Polyrun::Log.puts path
        0
      end

      def cmd_report_timing(argv)
        input = nil
        out_file = nil
        top = 30
        parser = OptionParser.new do |opts|
          opts.banner = "usage: polyrun report-timing -i FILE [-o PATH] [--top N]"
          opts.on("-i", "--input PATH", "Merged polyrun_timing.json (path => seconds)") { |v| input = v }
          opts.on("-o", "--output PATH", "Write summary to file instead of stdout") { |v| out_file = v }
          opts.on("--top N", Integer) { |v| top = v }
        end
        parser.parse!(argv)
        input ||= argv.first

        unless input && File.file?(input)
          Polyrun::Log.warn "report-timing: need -i FILE"
          return 2
        end

        merged = JSON.parse(File.read(File.expand_path(input)))
        text = Polyrun::Timing::Summary.format_slow_files(merged, top: top)
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
