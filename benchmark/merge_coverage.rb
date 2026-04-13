#!/usr/bin/env ruby
# Large-suite merge benchmark (SimpleCov-shaped blobs).
#
# Usage (from repo root):
#   ruby benchmark/merge_coverage.rb
#   bundle exec rake bench_merge
#
# Environment (defaults match spec/polyrun/coverage/merge_scale_spec.rb scale: ~100+ files × 300+ LOC):
#   MERGE_FILES       — source files per fragment (default 110)
#   MERGE_LINES       — lines per file (default 310)
#   MERGE_FRAGMENTS   — shard JSON count for multi-way merge (default 8)
#   MERGE_WARMUP      — warmup iterations (default 1)
#   MERGE_REPS        — repetitions for each timed block (default 3)
#   MERGE_REPS_TWO    — override for merge_two pair only (default: MERGE_REPS)
#   MERGE_GC_DISABLE  — set to 1 to disable GC during timed sections (stabler timings, not comparable across Ruby versions)
#   MERGE_WITH_META   — set to 1 so merge_files JSON includes meta (like collector output)

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "benchmark"
require "json"
require "tmpdir"
require "polyrun"

FILES = Integer(ENV.fetch("MERGE_FILES", "110"))
LINES = Integer(ENV.fetch("MERGE_LINES", "310"))
FRAGMENTS = Integer(ENV.fetch("MERGE_FRAGMENTS", "8"))
WARMUP = Integer(ENV.fetch("MERGE_WARMUP", "1"))
REPS_DEFAULT = Integer(ENV.fetch("MERGE_REPS", "3"))
REPS_TWO = Integer(ENV.fetch("MERGE_REPS_TWO", REPS_DEFAULT.to_s))
REPS_TREE = REPS_DEFAULT
REPS_DISK = REPS_DEFAULT
WITH_META = ENV["MERGE_WITH_META"] == "1"
GC_BENCH = ENV["MERGE_GC_DISABLE"] == "1"

def build_blob(rng, offset)
  h = {}
  FILES.times do |fi|
    path = "/project/app/models/aggregate_#{fi}.rb"
    lines = Array.new(LINES) do
      case rng.rand(100)
      when 0 then nil
      when 1 then "ignored"
      else rng.rand(0..15)
      end
    end
    lines.map! { |x| x.is_a?(Integer) ? (x + offset) % 8 : x }
    h[path] = {"lines" => lines}
  end
  h
end

def run_merge_two_pair
  rng = Random.new(42)
  a = build_blob(rng, 0)
  b = build_blob(rng, 1)
  Polyrun::Coverage::Merge.merge_two(a, b)
end

def run_merge_blob_tree
  rng = Random.new(42)
  blobs = Array.new(FRAGMENTS) { |i| build_blob(rng, i) }
  Polyrun::Coverage::Merge.merge_blob_tree(blobs)
end

def run_left_fold
  rng = Random.new(42)
  blobs = Array.new(FRAGMENTS) { |i| build_blob(rng, i) }
  blobs.reduce { |acc, el| Polyrun::Coverage::Merge.merge_two(acc, el) }
end

def run_merge_files_disk
  rng = Random.new(42)
  Dir.mktmpdir("polyrun_merge_bench") do |dir|
    paths = Array.new(FRAGMENTS) do |i|
      blob = build_blob(rng, i)
      payload =
        if WITH_META
          {
            "coverage" => blob,
            "meta" => {
              "polyrun_coverage_root" => "/project",
              "polyrun_coverage_groups" => {"Models" => "app/models/**/*.rb"}
            }
          }
        else
          {"coverage" => blob}
        end
      p = File.join(dir, "part#{i}.json")
      File.write(p, JSON.generate(payload))
      p
    end
    Polyrun::Coverage::Merge.merge_files(paths)
  end
end

def run_merge_fragments_full
  rng = Random.new(42)
  Dir.mktmpdir("polyrun_merge_bench") do |dir|
    paths = Array.new(FRAGMENTS) do |i|
      blob = build_blob(rng, i)
      payload = {
        "coverage" => blob,
        "meta" => {
          "polyrun_coverage_root" => "/project",
          "polyrun_coverage_groups" => {"Models" => "app/models/**/*.rb"}
        }
      }
      p = File.join(dir, "part#{i}.json")
      File.write(p, JSON.generate(payload))
      p
    end
    Polyrun::Coverage::Merge.merge_fragments(paths)
  end
end

def line_count(blob)
  blob.values.sum { |f| (f["lines"] || []).size }
end

def with_gc_maybe
  if GC_BENCH
    GC.disable
    yield
    GC.enable
    GC.start
  else
    yield
  end
end

WARMUP.times do
  m = run_merge_two_pair
  raise "empty merge" if m.empty?

  line_count(m)
end

puts "Polyrun coverage merge benchmark"
puts "  Polyrun #{Polyrun::VERSION} | Ruby #{RUBY_VERSION}"
puts "  files per fragment: #{FILES}"
puts "  lines per file:     #{LINES}"
puts "  line rows / fragment: ~#{FILES * LINES}"
puts "  fragments:          #{FRAGMENTS}"
puts "  MERGE_WITH_META:    #{WITH_META}"
puts "  MERGE_GC_DISABLE:   #{GC_BENCH}"
puts

width = 42

with_gc_maybe do
  Benchmark.bm(width) do |x|
    x.report("merge_two (2× suite) [#{REPS_TWO}]") { REPS_TWO.times { run_merge_two_pair } }

    x.report("merge_blob_tree (balanced) [#{REPS_TREE}]") { REPS_TREE.times { run_merge_blob_tree } }

    x.report("merge_two left_fold (naive) [#{REPS_TREE}]") { REPS_TREE.times { run_left_fold } }

    x.report("merge_files (disk→merge_files) [#{REPS_DISK}]") { REPS_DISK.times { run_merge_files_disk } }

    x.report("merge_fragments (+meta/groups) [#{REPS_DISK}]") { REPS_DISK.times { run_merge_fragments_full } }
  end
end

m = run_merge_blob_tree
puts
puts "Sanity: merged file keys: #{m.size} (expected #{FILES})"
puts "Sample integer line sum (first file): #{m.values.first['lines'].compact.grep(Integer).sum}"
