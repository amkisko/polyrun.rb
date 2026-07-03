#!/usr/bin/env ruby
# frozen_string_literal: true

# Measures stdlib Coverage.peek_result overhead (per-example cost estimator).
# Usage: ruby benchmark/spec_quality_peek.rb [REPS] [LINES_PER_FILE]
#
# REPS — peek calls per iteration (default 1000)
# LINES_PER_FILE — synthetic coverage array size (default 310)

require "benchmark"
require "coverage"
require "fileutils"

reps = Integer(ARGV[0] || 1000)
line_count = Integer(ARGV[1] || 310)

Coverage.start(lines: true)
path = File.expand_path("tmp/spec_quality_bench_target.rb", __dir__)
FileUtils.mkdir_p(File.dirname(path))
File.write(path, "def bench\n#{"  1\n" * line_count}end\n")
load path
bench

peek = Benchmark.realtime do
  reps.times { Coverage.peek_result }
end

diff = Benchmark.realtime do
  before = Coverage.peek_result
  reps.times do
    bench
    after = Coverage.peek_result
    before = after
  end
end

puts "peek_result: #{format('%.4f', peek)}s total, #{format('%.6f', peek / reps)}s per call (#{reps} reps, #{line_count} lines/file)"
puts "peek diff loop: #{format('%.4f', diff)}s total, #{format('%.6f', diff / reps)}s per example-pair (#{reps} reps)"
