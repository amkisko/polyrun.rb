#!/usr/bin/env ruby
# frozen_string_literal: true

# Pressure / load bench for Polyrun coverage merge.
#
# Usage:
#   bundle exec ruby benchmarks/load.rb
#   SCENARIO=matrix MERGE_FILES=200 bundle exec ruby benchmarks/load.rb
#   SCENARIO=disk TARGET_FACTOR=0.85 bundle exec ruby benchmarks/load.rb
#
# Env:
#   SCENARIO=matrix|disk|tree|two|heavy (default matrix)
#   MERGE_FILES, MERGE_LINES, MERGE_FRAGMENTS — workload size
#   MERGE_REPS — timed repetitions (default 2)
#   TARGET_FACTOR — next-round resource ceiling vs baseline (default 0.85)
#   PRESSURE_POLYRUN_LIB — optional override for lib/ path

lib = ENV["PRESSURE_POLYRUN_LIB"] || File.expand_path("../lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require "json"
require "tmpdir"
require "polyrun"
require "polyrun/benchmark/pressure"

module Polyrun
  module Bench
    module Load
      module_function

      def run!
        files = env_int("MERGE_FILES", 110)
        lines = env_int("MERGE_LINES", 310)
        fragments = env_int("MERGE_FRAGMENTS", 8)
        reps = env_int("MERGE_REPS", 2)
        factor = ENV.fetch("TARGET_FACTOR", Polyrun::Benchmark::Pressure::DEFAULT_TARGET_FACTOR.to_s).to_f
        scenario = ENV.fetch("SCENARIO", "matrix")

        puts "Polyrun pressure load scenario=#{scenario} files=#{files} lines=#{lines} fragments=#{fragments} reps=#{reps}"

        results =
          case scenario
          when "two" then [run_two!(files, lines, reps)]
          when "tree" then [run_tree!(files, lines, fragments, reps)]
          when "disk" then [run_disk!(files, lines, fragments, reps)]
          when "heavy" then [run_heavy!(files, lines, fragments, reps)]
          when "matrix" then run_matrix!(files, lines, fragments, reps, factor)
          else
            raise "Unknown SCENARIO=#{scenario.inspect}"
          end

        path = Polyrun::Benchmark::Pressure.write_results!(results, repository_root: File.expand_path("..", __dir__))
        results.each { |row| puts row["report"] }
        puts "wrote #{path}"
        exit_code = (results.any? { |row| row["pass"] == false }) ? 1 : 0
        exit exit_code
      end

      def run_matrix!(files, lines, fragments, reps, factor)
        baseline_disk = run_disk!(files, lines, fragments, reps, label: "baseline_disk")
        targets = Polyrun::Benchmark::Pressure.targets_from(baseline_disk["metrics"], factor: factor)

        hotter_files = (files * 1.5).ceil
        hotter_fragments = [fragments + 4, fragments * 2].min
        heavy = run_disk!(
          hotter_files,
          lines,
          hotter_fragments,
          reps,
          label: "pressure_disk_#{hotter_files}x#{lines}x#{hotter_fragments}",
          targets: scale_targets_for_ops(targets, baseline_disk["ops"], hotter_fragments)
        )

        tree = run_tree!(files, lines, fragments, reps, label: "tree")
        two = run_two!(files, lines, reps, label: "merge_two")
        [baseline_disk, heavy, tree, two]
      end

      def run_two!(files, lines, reps, label: "merge_two", targets: nil)
        Polyrun::Benchmark::Pressure.measure(label: label, ops: reps, extras: {"targets" => targets}) do
          reps.times do
            rng = Random.new(42)
            a = build_blob(rng, files, lines, 0)
            b = build_blob(rng, files, lines, 1)
            Polyrun::Coverage::Merge.merge_two(a, b)
          end
        end
      end

      def run_tree!(files, lines, fragments, reps, label: "merge_tree", targets: nil)
        Polyrun::Benchmark::Pressure.measure(label: label, ops: reps * fragments, extras: {"targets" => targets}) do
          reps.times do
            rng = Random.new(42)
            blobs = Array.new(fragments) { |i| build_blob(rng, files, lines, i) }
            Polyrun::Coverage::Merge.merge_blob_tree(blobs)
          end
        end
      end

      def run_disk!(files, lines, fragments, reps, label: "merge_disk", targets: nil)
        storage = 0
        result = Polyrun::Benchmark::Pressure.measure(
          label: label,
          ops: reps * fragments,
          extras: {"targets" => targets}
        ) do
          reps.times do
            rng = Random.new(42)
            Dir.mktmpdir("polyrun_pressure") do |dir|
              paths = Array.new(fragments) do |i|
                blob = build_blob(rng, files, lines, i)
                path = File.join(dir, "part#{i}.json")
                payload = JSON.generate({"coverage" => blob})
                storage += payload.bytesize
                File.write(path, payload)
                path
              end
              Polyrun::Coverage::Merge.merge_files(paths)
            end
          end
        end
        result["metrics"]["storage_delta_bytes"] += storage
        result["report"] = Polyrun::Benchmark::Pressure.format_report(result)
        result
      end

      def run_heavy!(files, lines, fragments, reps)
        run_disk!(files * 2, lines, fragments * 2, reps, label: "heavy_disk")
      end

      def build_blob(rng, files, lines, offset)
        h = {}
        files.times do |fi|
          path = "/project/app/models/aggregate_#{fi}.rb"
          row = Array.new(lines) do
            case rng.rand(100)
            when 0 then nil
            when 1 then "ignored"
            else rng.rand(0..15)
            end
          end
          row.map! { |x| x.is_a?(Integer) ? (x + offset) % 8 : x }
          h[path] = {"lines" => row}
        end
        h
      end

      def scale_targets_for_ops(targets, baseline_ops, new_ops)
        return targets if baseline_ops.nil? || baseline_ops <= 0 || new_ops.nil?

        ratio = new_ops.to_f / baseline_ops
        targets.transform_values { |v| v.nil? ? nil : v * ratio }
      end

      def env_int(name, default)
        Integer(ENV.fetch(name, default.to_s))
      end
    end
  end
end

Polyrun::Bench::Load.run! if $PROGRAM_NAME == __FILE__
