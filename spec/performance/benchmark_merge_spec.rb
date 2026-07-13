require "spec_helper"
require_relative "../support/benchmark_merge_helpers"

# Performance benchmarks for native coverage merge paths.
# rubocop:disable RSpec/DescribeClass, RSpec/NoExpectationExample
RSpec.describe "Coverage merge benchmarks", :benchmark do
  include BenchmarkMergeHelpers

  let(:files) { Integer(ENV.fetch("BENCH_FILES", "110")) }
  let(:lines_per_file) { Integer(ENV.fetch("BENCH_LINES", "310")) }
  let(:fragments) { Integer(ENV.fetch("BENCH_FRAGMENTS", "8")) }
  let(:merge_reps) { Integer(ENV.fetch("BENCH_MERGE_REPS", "3")) }
  let(:line_count_reps) { Integer(ENV.fetch("BENCH_LINE_COUNT_REPS", "5")) }

  it "compares merge_two, merge_blob_tree, and native vs Ruby ratio", :aggregate_failures do
    random = Random.new(42)
    left = build_blob(files: files, lines_per_file: lines_per_file, random: random, offset: 0)
    right = build_blob(files: files, lines_per_file: lines_per_file, random: random, offset: 1)
    fragment_blobs = Array.new(fragments) do |index|
      build_blob(files: files, lines_per_file: lines_per_file, random: random, offset: index)
    end

    merge_two_time = Benchmark.realtime { merge_reps.times { Polyrun::Coverage::Merge.merge_two(left, right) } }
    tree_time = Benchmark.realtime { merge_reps.times { Polyrun::Coverage::Merge.merge_blob_tree(fragment_blobs) } }

    BenchmarkProfile.log "\n  Coverage merge (files=#{files}, lines=#{lines_per_file}, fragments=#{fragments}, reps=#{merge_reps}):"
    BenchmarkProfile.log "    native acceleration: #{Polyrun::Coverage::Merge.native_acceleration?}"
    BenchmarkProfile.log "    merge_two:        #{merge_two_time.round(4)}s"
    BenchmarkProfile.log "    merge_blob_tree:  #{tree_time.round(4)}s"
    BenchmarkProfile.log "    per merge_two:    #{(merge_two_time / merge_reps * 1000).round(2)}ms"

    if Polyrun::Coverage::Merge.native_acceleration?
      ruby_merge_time = Benchmark.realtime do
        merge_reps.times { Polyrun::Coverage::Merge.merge_two_ruby(left, right) }
      end
      native_merge_time = Benchmark.realtime do
        merge_reps.times { Polyrun::Coverage::MergeNative.merge_two(left, right) }
      end
      log_native_ruby_ratio("merge_two", ruby_merge_time, native_merge_time)
    end
  end

  it "compares line_counts across all files and native vs Ruby ratio", :aggregate_failures do
    random = Random.new(42)
    blob = build_blob(files: files, lines_per_file: lines_per_file, random: random, offset: 0)

    line_counts_time = Benchmark.realtime do
      line_count_reps.times do
        blob.each_value { |entry| Polyrun::Coverage::Merge.line_counts(entry) }
      end
    end

    BenchmarkProfile.log "\n  line_counts (files=#{files}, lines=#{lines_per_file}, reps=#{line_count_reps}):"
    BenchmarkProfile.log "    total:            #{line_counts_time.round(4)}s"
    BenchmarkProfile.log "    per file sweep:   #{(line_counts_time / line_count_reps * 1000).round(2)}ms"

    if Polyrun::Coverage::Merge.native_acceleration?
      ruby_line_counts_time = Benchmark.realtime do
        line_count_reps.times do
          blob.each_value { |entry| Polyrun::Coverage::Merge.line_counts_ruby(entry) }
        end
      end
      native_line_counts_time = Benchmark.realtime do
        line_count_reps.times do
          blob.each_value { |entry| Polyrun::Coverage::MergeNative.line_counts(entry) }
        end
      end
      log_native_ruby_ratio("line_counts sweep", ruby_line_counts_time, native_line_counts_time)
    end
  end

  it "compares branch-heavy merge_two and native vs Ruby ratio", :aggregate_failures do
    random = Random.new(7)
    left = build_blob(files: files, lines_per_file: lines_per_file, random: random, offset: 0, branches: true)
    right = build_blob(files: files, lines_per_file: lines_per_file, random: random, offset: 1, branches: true)

    branch_merge_time = Benchmark.realtime do
      merge_reps.times { Polyrun::Coverage::Merge.merge_two(left, right) }
    end

    BenchmarkProfile.log "\n  Branch-heavy merge (files=#{files}, lines=#{lines_per_file}, reps=#{merge_reps}):"
    BenchmarkProfile.log "    merge_two:        #{branch_merge_time.round(4)}s"
    BenchmarkProfile.log "    per merge_two:    #{(branch_merge_time / merge_reps * 1000).round(2)}ms"

    if Polyrun::Coverage::Merge.native_acceleration?
      ruby_branch_time = Benchmark.realtime do
        merge_reps.times { Polyrun::Coverage::Merge.merge_two_ruby(left, right) }
      end
      native_branch_time = Benchmark.realtime do
        merge_reps.times { Polyrun::Coverage::MergeNative.merge_two(left, right) }
      end
      log_native_ruby_ratio("branch-heavy merge_two", ruby_branch_time, native_branch_time)
    end
  end

  it "profiles memory for merge_two on the largest realistic synthetic blob", :aggregate_failures do
    skip "Set BENCH_MEMORY=1 to run memory_profiler" unless ENV["BENCH_MEMORY"] == "1"

    require "memory_profiler"

    random = Random.new(42)
    left = build_blob(files: files, lines_per_file: lines_per_file, random: random, offset: 0, branches: true)
    right = build_blob(files: files, lines_per_file: lines_per_file, random: random, offset: 1, branches: true)
    iterations = Integer(ENV.fetch("BENCH_MEMORY_REPS", "3"))

    report = MemoryProfiler.report do
      iterations.times { Polyrun::Coverage::Merge.merge_two(left, right) }
    end

    BenchmarkProfile.log "\n  Memory merge_two (files=#{files}, lines=#{lines_per_file}, branches=yes, reps=#{iterations}):"
    BenchmarkProfile.log "    native acceleration: #{Polyrun::Coverage::Merge.native_acceleration?}"
    BenchmarkProfile.log "    Total allocated: #{report.total_allocated_memsize / 1024}KB (#{report.total_allocated} objects)"
    BenchmarkProfile.log "    Total retained:  #{report.total_retained_memsize / 1024}KB"
    BenchmarkProfile.log "    Avg per merge:   #{(report.total_allocated_memsize / iterations / 1024.0).round(2)}KB"

    if Polyrun::Coverage::Merge.native_acceleration?
      ruby_report = MemoryProfiler.report do
        iterations.times { Polyrun::Coverage::Merge.merge_two_ruby(left, right) }
      end
      BenchmarkProfile.log "    Ruby path allocated: #{ruby_report.total_allocated_memsize / 1024}KB"
      BenchmarkProfile.log "    Native path allocated: #{report.total_allocated_memsize / 1024}KB"
    end
  end
end
# rubocop:enable RSpec/DescribeClass, RSpec/NoExpectationExample
