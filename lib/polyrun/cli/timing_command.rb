require "optparse"

module Polyrun
  class CLI
    module TimingCommand
      private

      def cmd_merge_timing(argv)
        inputs = []
        output = "polyrun_timing.json"
        parser = OptionParser.new do |opts|
          opts.banner = "usage: polyrun merge-timing [-i FILE]... [-o OUT] [FILE...]"
          opts.on("-i", "--input FILE", "Timing JSON fragment (repeatable)") { |f| inputs << f }
          opts.on("-o", "--output PATH", String) { |v| output = v }
        end
        parser.parse!(argv)
        inputs.concat(argv) if inputs.empty?

        if inputs.empty?
          Polyrun::Log.warn "merge-timing: need -i FILE or positional paths"
          return 2
        end

        out_abs = File.expand_path(output)
        Polyrun::Timing::Merge.merge_and_write(inputs.map { |p| File.expand_path(p) }, out_abs)
        Polyrun::Log.puts out_abs
        0
      end
    end
  end
end
