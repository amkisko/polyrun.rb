require "spec_helper"
require "stringio"

# Optional CPU/allocation profiles and IPS comparisons for local optimization work.
# rubocop:disable RSpec/DescribeClass, RSpec/NoExpectationExample
RSpec.describe "Performance profiling", :benchmark do
  let(:iterations) { Integer(ENV.fetch("BENCH_PROF_ITERATIONS", "2000")) }
  let(:files) { Integer(ENV.fetch("BENCH_FILES", "40")) }
  let(:lines_per_file) { Integer(ENV.fetch("BENCH_LINES", "200")) }

  def build_merge_pair
    random = Random.new(42)
    build = lambda do |offset|
      blob = {}
      files.times do |file_index|
        path = "/project/app/models/profile_#{file_index}.rb"
        blob[path] = {"lines" => Array.new(lines_per_file) { random.rand(0..7) + offset }}
      end
      blob
    end
    [build.call(0), build.call(1)]
  end

  describe "stackprof profiles" do
    before { skip "Set STACKPROF=1 to generate StackProf profiles" unless ENV["STACKPROF"] == "1" }

    it "profiles merge_two on CPU", :aggregate_failures do
      left, right = build_merge_pair

      path = BenchmarkProfiler.profile_cpu(label: "stackprof_merge_two", iterations: iterations) do
        Polyrun::Coverage::Merge.merge_two(left, right)
      end

      expect(File).to exist(path)
    end

    it "profiles snapshot_peek allocations", :aggregate_failures do
      require "coverage"
      require "fileutils"

      bench_dir = File.join(Dir.tmpdir, "polyrun_stackprof_peek_#{Process.pid}")
      FileUtils.mkdir_p(bench_dir)
      files.times do |index|
        path = File.join(bench_dir, "file_#{index}.rb")
        body = Array.new(lines_per_file) { "  @cov = 1" }.join("\n")
        File.write(path, "def prof_peek_#{index}\n#{body}\nend\n")
      end

      Coverage.start(lines: true)
      files.times do |index|
        load File.join(bench_dir, "file_#{index}.rb")
        send("prof_peek_#{index}")
      end

      path = BenchmarkProfiler.profile_allocations(label: "stackprof_snapshot_peek", iterations: iterations / 5) do
        Polyrun::Coverage::ExampleDiff.snapshot_peek(Coverage.peek_result)
      end

      expect(File).to exist(path)
    ensure
      FileUtils.rm_rf(bench_dir) if bench_dir && File.directory?(bench_dir)
    end
  end

  describe "benchmark-ips comparisons" do
    before { skip "Set BENCHMARK_IPS=1 to compare iterations per second" unless ENV["BENCHMARK_IPS"] == "1" }

    it "compares merge_two versus merge_blob_tree throughput", :aggregate_failures do
      left, right = build_merge_pair
      random = Random.new(7)
      fragment_blobs = Array.new(4) do |index|
        blob = {}
        files.times do |file_index|
          path = "/project/app/models/profile_#{file_index}.rb"
          blob[path] = {"lines" => Array.new(lines_per_file) { random.rand(0..7) + index }}
        end
        blob
      end

      path = BenchmarkProfiler.compare_ips do |comparison|
        comparison.config(time: 1, warmup: 1)

        comparison.report("merge_two") do
          Polyrun::Coverage::Merge.merge_two(left, right)
        end

        comparison.report("merge_blob_tree_4") do
          Polyrun::Coverage::Merge.merge_blob_tree(fragment_blobs)
        end

        comparison.compare!
      end

      expect(File).to exist(path)
    end
  end
end
# rubocop:enable RSpec/DescribeClass, RSpec/NoExpectationExample
