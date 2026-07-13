require "optparse"

require_relative "../benchmark/profile"
require_relative "../benchmark/report"

module Polyrun
  class CLI
    module BenchmarkCommands
      private

      def cmd_report_benchmark(argv)
        input = nil
        out_file = nil
        report_format = "text"
        OptionParser.new do |opts|
          opts.banner = "usage: polyrun report-benchmark -i FILE [-o PATH] [--format text|json|csv|markdown]"
          opts.on("-i", "--input PATH", "Benchmark profile .json or .log from tmp/benchmarks/") { |v| input = v }
          opts.on("-o", "--output PATH", "Write report to file instead of stdout") { |v| out_file = v }
          opts.on("--format VAL", "text (default), json, csv, or markdown") { |v| report_format = v }
        end.parse!(argv)
        input ||= argv.first

        unless input && File.file?(input)
          Polyrun::Log.warn "report-benchmark: need -i FILE"
          return 2
        end

        data = Polyrun::Benchmark::Report.load(File.expand_path(input))
        begin
          text = Polyrun::Benchmark::Report.render(data, format: report_format)
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

      def cmd_bench(argv)
        tag = "benchmark"
        paths = %w[spec/performance/benchmark_spec.rb spec/performance/benchmark_merge_spec.rb]
        env = {
          "BENCH_FILES" => ENV.fetch("BENCH_FILES", "110"),
          "BENCH_LINES" => ENV.fetch("BENCH_LINES", "310"),
          "BENCH_FRAGMENTS" => ENV.fetch("BENCH_FRAGMENTS", "8"),
          "BENCH_MERGE_REPS" => ENV.fetch("BENCH_MERGE_REPS", "3"),
          "BENCH_LINE_COUNT_REPS" => ENV.fetch("BENCH_LINE_COUNT_REPS", "5"),
          "BENCH_PEEK_REPS" => ENV.fetch("BENCH_PEEK_REPS", "200")
        }
        formats = ENV["POLYRUN_BENCH_FORMATS"]
        env["POLYRUN_BENCH_FORMATS"] = formats if formats && !formats.to_s.strip.empty?
        bench_argv = paths + ["--tag", tag]
        bench_argv.concat(argv) unless argv.empty?
        Polyrun::Log.warn "polyrun bench: running performance specs (#{paths.join(", ")})" if @verbose
        success = system(env, "bundle", "exec", "rspec", *bench_argv)
        success ? 0 : ($?.exitstatus || 1)
      end
    end
  end
end
