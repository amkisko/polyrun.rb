require "spec_helper"
require "benchmark"
require "stringio"

# Performance benchmarks for coverage merge and spec-quality hot paths.
# rubocop:disable RSpec/DescribeClass, RSpec/NoExpectationExample
RSpec.describe "Performance benchmarks", :benchmark do
  let(:files) { Integer(ENV.fetch("BENCH_FILES", "110")) }
  let(:lines_per_file) { Integer(ENV.fetch("BENCH_LINES", "310")) }
  let(:fragments) { Integer(ENV.fetch("BENCH_FRAGMENTS", "8")) }
  let(:merge_reps) { Integer(ENV.fetch("BENCH_MERGE_REPS", "3")) }
  let(:peek_reps) { Integer(ENV.fetch("BENCH_PEEK_REPS", "200")) }

  def build_blob(random, offset)
    blob = {}
    files.times do |file_index|
      path = "/project/app/models/aggregate_#{file_index}.rb"
      line_hits = Array.new(lines_per_file) do
        case random.rand(100)
        when 0 then nil
        when 1 then "ignored"
        else random.rand(0..15)
        end
      end
      line_hits.map! { |hit| hit.is_a?(Integer) ? (hit + offset) % 8 : hit }
      blob[path] = {"lines" => line_hits}
    end
    blob
  end

  describe "coverage merge" do
    it "compares merge_two, merge_blob_tree, and merge_fragments", :aggregate_failures do
      random = Random.new(42)
      left = build_blob(random, 0)
      right = build_blob(random, 1)
      fragment_blobs = Array.new(fragments) { |index| build_blob(random, index) }

      merge_two_time = Benchmark.realtime { merge_reps.times { Polyrun::Coverage::Merge.merge_two(left, right) } }
      tree_time = Benchmark.realtime { merge_reps.times { Polyrun::Coverage::Merge.merge_blob_tree(fragment_blobs) } }

      BenchmarkProfile.log "\n  Coverage merge (files=#{files}, lines=#{lines_per_file}, fragments=#{fragments}, reps=#{merge_reps}):"
      BenchmarkProfile.log "    native merge_line_arrays: #{Polyrun::Coverage::Merge.native_merge_line_arrays?}"
      BenchmarkProfile.log "    merge_two:        #{merge_two_time.round(4)}s"
      BenchmarkProfile.log "    merge_blob_tree:  #{tree_time.round(4)}s"
      BenchmarkProfile.log "    per merge_two:    #{(merge_two_time / merge_reps * 1000).round(2)}ms"
    end
  end

  describe "spec quality peek" do
    it "compares peek_result, snapshot_peek, and diff against raw peek", :aggregate_failures do
      require "coverage"
      require "fileutils"

      bench_dir = File.join(Dir.tmpdir, "polyrun_bench_cov_#{Process.pid}")
      lib_dir = File.join(bench_dir, "lib")
      spec_dir = File.join(bench_dir, "spec")
      FileUtils.mkdir_p(lib_dir)
      FileUtils.mkdir_p(spec_dir)
      files.times do |index|
        target_dir = index.even? ? lib_dir : spec_dir
        path = File.join(target_dir, "file_#{index}.rb")
        body = Array.new(lines_per_file) { "  @cov = 1" }.join("\n")
        File.write(path, "def bench_method_#{index}\n#{body}\nend\n")
      end

      Coverage.start(lines: true) unless Coverage.running?
      files.times do |index|
        load File.join(index.even? ? lib_dir : spec_dir, "file_#{index}.rb")
        send(:"bench_method_#{index}")
      end

      peek_time = Benchmark.realtime { peek_reps.times { Coverage.peek_result } }
      snapshot_time = Benchmark.realtime { peek_reps.times { Polyrun::Coverage::ExampleDiff.snapshot_peek(Coverage.peek_result) } }

      diff_pair_time = Benchmark.realtime do
        peek_reps.times do
          before = Polyrun::Coverage::ExampleDiff.snapshot_peek(Coverage.peek_result)
          send(:bench_method_0)
          Polyrun::Coverage::ExampleDiff.diff(before, Coverage.peek_result)
        end
      end

      scoped_snapshot_time = Benchmark.realtime do
        peek_reps.times do
          Polyrun::Coverage::ExampleDiff.snapshot_peek(
            Coverage.peek_result,
            root: bench_dir,
            track_under: %w[lib app]
          )
        end
      end

      scoped_diff_time = Benchmark.realtime do
        peek_reps.times do
          before = Polyrun::Coverage::ExampleDiff.snapshot_peek(
            Coverage.peek_result,
            root: bench_dir,
            track_under: %w[lib app]
          )
          send(:bench_method_0)
          Polyrun::Coverage::ExampleDiff.diff(
            before,
            Coverage.peek_result,
            root: bench_dir,
            track_under: %w[lib app]
          )
        end
      end

      BenchmarkProfile.log "\n  Spec quality peek (loaded files=#{files}, lines=#{lines_per_file}, reps=#{peek_reps}):"
      BenchmarkProfile.log "    Coverage.peek_result:      #{peek_time.round(4)}s"
      BenchmarkProfile.log "    ExampleDiff.snapshot_peek: #{snapshot_time.round(4)}s"
      BenchmarkProfile.log "    scoped snapshot (lib/):    #{scoped_snapshot_time.round(4)}s"
      BenchmarkProfile.log "    snapshot + diff (pair):    #{diff_pair_time.round(4)}s"
      BenchmarkProfile.log "    scoped snapshot + diff:    #{scoped_diff_time.round(4)}s"
      BenchmarkProfile.log "    per scoped example-pair:   #{(scoped_diff_time / peek_reps * 1000).round(3)}ms"
    ensure
      FileUtils.rm_rf(bench_dir) if bench_dir && File.directory?(bench_dir)
    end

    it "measures memory allocations for snapshot_peek and diff pair", :aggregate_failures do
      skip "Set BENCH_MEMORY=1 to run memory_profiler" unless ENV["BENCH_MEMORY"] == "1"

      require "coverage"
      require "memory_profiler"
      require "fileutils"

      bench_dir = File.join(Dir.tmpdir, "polyrun_bench_mem_#{Process.pid}")
      FileUtils.mkdir_p(bench_dir)
      sample_files = [files, 20].min
      sample_files.times do |index|
        path = File.join(bench_dir, "file_#{index}.rb")
        body = Array.new(lines_per_file) { "  @cov = 1" }.join("\n")
        File.write(path, "def mem_bench_#{index}\n#{body}\nend\n")
      end

      Coverage.start(lines: true) unless Coverage.running?
      sample_files.times do |index|
        load File.join(bench_dir, "file_#{index}.rb")
        send("mem_bench_#{index}")
      end

      iterations = Integer(ENV.fetch("BENCH_MEMORY_REPS", "100"))
      report = MemoryProfiler.report do
        iterations.times do
          before = Polyrun::Coverage::ExampleDiff.snapshot_peek(Coverage.peek_result)
          send(:mem_bench_0)
          Polyrun::Coverage::ExampleDiff.diff(before, Coverage.peek_result)
        end
      end

      BenchmarkProfile.log "\n  Memory (snapshot + diff, #{iterations} iterations, #{sample_files} files):"
      BenchmarkProfile.log "    Total allocated: #{report.total_allocated_memsize / 1024}KB (#{report.total_allocated} objects)"
      BenchmarkProfile.log "    Total retained:  #{report.total_retained_memsize / 1024}KB"
      BenchmarkProfile.log "    Avg per pair:    #{(report.total_allocated_memsize / iterations / 1024.0).round(2)}KB"
    ensure
      FileUtils.rm_rf(bench_dir) if bench_dir && File.directory?(bench_dir)
    end
  end
end
# rubocop:enable RSpec/DescribeClass, RSpec/NoExpectationExample
