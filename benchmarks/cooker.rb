#!/usr/bin/env ruby
# frozen_string_literal: true

# Pressure-cooker harness for amkisko/pressure-benchmarking.
#
#   SCENARIO=calibrate|baseline|stress|propose|measure|gate|write bundle exec ruby benchmarks/cooker.rb
#
# Env: MERGE_FILES MERGE_LINES MERGE_FRAGMENTS SAMPLES HEADROOM COOKER_STAGE

lib = ENV["PRESSURE_POLYRUN_LIB"] || File.expand_path("../lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require "fileutils"
require "json"
require "tmpdir"
require "polyrun"
require "polyrun/benchmark/pressure"

module Polyrun
  module Bench
    module CookerRun
      ROOT = File.expand_path("..", __dir__)
      CEILINGS = File.join(ROOT, "benchmarks", "ceilings.json")
      OUTPUT = File.join(ROOT, "benchmarks", "output")

      module_function

      def run!
        scenario = ENV.fetch("SCENARIO", "calibrate")
        files = env_int("MERGE_FILES", 40)
        lines = env_int("MERGE_LINES", 80)
        fragments = env_int("MERGE_FRAGMENTS", 6)
        samples = env_int("SAMPLES", Polyrun::Benchmark::Pressure::Cooker::DEFAULT_SAMPLES)
        headroom = ENV.fetch("HEADROOM", Polyrun::Benchmark::Pressure::Cooker::DEFAULT_HEADROOM.to_s).to_f

        result =
          case scenario
          when "calibrate" then calibrate!
          when "baseline" then measure_load!(files, lines, fragments, samples, label: "baseline_L0")
          when "stress"
            measure_load!(
              (files * 1.5).ceil,
              lines,
              [fragments + 4, fragments * 2].min,
              samples,
              label: "stress_L1"
            )
          when "propose" then propose!(files, lines, fragments, samples, headroom)
          when "measure" then measure_load!(files, lines, fragments, samples, label: ENV.fetch("COOKER_STAGE", "measure"))
          when "gate" then gate!(files, lines, fragments, samples)
          when "write" then write_ceilings_from_env!
          else
            raise "Unknown SCENARIO=#{scenario.inspect}"
          end

        path = File.join(OUTPUT, "#{Time.now.utc.strftime("%Y%m%d%H%M%S")}_cooker_#{scenario}.json")
        FileUtils.mkdir_p(OUTPUT)
        File.write(path, JSON.pretty_generate(result))
        puts JSON.pretty_generate((result.is_a?(Hash) && result["report"]) ? {"report" => result["report"], "pass" => result["pass"]} : result)
        puts "wrote #{path}"
        exit((result.is_a?(Hash) && result.key?("pass") && result["pass"] == false) ? 1 : 0)
      end

      def calibrate!
        stages = [
          ["tiny_two", 1, -> { merge_two_once(10, 20) }],
          ["medium_two", 2, -> { merge_two_once(40, 80) }],
          ["disk_fold", 3, -> { disk_once(30, 40, 4) }]
        ]
        Polyrun::Benchmark::Pressure::Cooker.calibrate!(stages)
      end

      def measure_load!(files, lines, fragments, samples, label:)
        storages = []
        agg = Polyrun::Benchmark::Pressure::Cooker.measure_samples(
          n: samples,
          label: label,
          ops: fragments,
          extras: {"basis" => "median"}
        ) do
          bytes = 0
          disk_once(files, lines, fragments) { |n| bytes += n }
          storages << bytes
        end
        storage_med = Polyrun::Benchmark::Pressure::Cooker.percentile(storages, 0.5)
        agg["metrics"]["storage_delta_bytes"] = storage_med
        agg["series"]["storage_delta_bytes"] = {
          "basis_value" => storage_med,
          "samples" => storages,
          "median" => storage_med,
          "max" => storages.max,
          "min" => storages.min
        }
        agg["network"] = "not_in_scope"
        agg["memory_probe_class"] = "process_lifetime"
        agg["report"] = format(
          "%s n=%d wall_med=%.4fs cpu_med=%.4fs alloc_med=%.0f storage=%.0f gateable=%s",
          label,
          samples,
          agg["metrics"]["wall_s"].to_f,
          agg["metrics"]["cpu_s"].to_f,
          agg["metrics"]["allocated_objects"].to_f,
          storage_med.to_f,
          agg["gateable"]
        )
        agg
      end

      def propose!(files, lines, fragments, samples, headroom)
        stress = measure_load!(
          (files * 1.5).ceil,
          lines,
          [fragments + 4, fragments * 2].min,
          samples,
          label: "propose_L1"
        )
        ceilings = Polyrun::Benchmark::Pressure::Cooker.propose_ceilings(
          stress["series"],
          headroom: headroom,
          keys: %w[wall_s cpu_s allocated_objects storage_delta_bytes]
        )
        {
          "pass" => stress["gateable"],
          "stress" => stress,
          "ceilings" => ceilings,
          "headroom" => headroom,
          "propose_basis" => "median",
          "report" => "proposed ceilings headroom=#{headroom}: #{ceilings.inspect}"
        }
      end

      def gate!(files, lines, fragments, samples)
        ceilings_doc = Polyrun::Benchmark::Pressure::Cooker.load_ceilings(CEILINGS)
        ceilings = ceilings_doc["ceilings"] || ceilings_doc
        raise "missing ceilings at #{CEILINGS}; run SCENARIO=propose then SCENARIO=write" if ceilings.nil? || ceilings.empty?

        measured = measure_load!(files, lines, fragments, samples, label: "gate_L1")
        result = Polyrun::Benchmark::Pressure::Cooker.gate(measured, ceilings)
        result["report"] = "gate pass=#{result["pass"]} failures=#{result["failures"].inspect}"
        result["measured"] = measured
        result
      end

      def write_ceilings_from_env!
        raw = ENV.fetch("CEILINGS_JSON")
        ceilings = JSON.parse(raw)
        path = Polyrun::Benchmark::Pressure::Cooker.write_ceilings!(
          CEILINGS,
          ceilings,
          meta: {
            "propose_basis" => "median",
            "headroom" => ENV.fetch("HEADROOM", "1.15").to_f,
            "memory_probe_class" => "process_lifetime",
            "network" => "not_in_scope"
          }
        )
        {"pass" => true, "path" => path, "ceilings" => ceilings, "report" => "wrote #{path}"}
      end

      def merge_two_once(files, lines)
        rng = Random.new(42)
        a = build_blob(rng, files, lines, 0)
        b = build_blob(rng, files, lines, 1)
        Polyrun::Coverage::Merge.merge_two(a, b)
      end

      def disk_once(files, lines, fragments)
        rng = Random.new(42)
        Dir.mktmpdir("polyrun_cooker") do |dir|
          paths = Array.new(fragments) do |i|
            blob = build_blob(rng, files, lines, i)
            path = File.join(dir, "part#{i}.json")
            payload = JSON.fast_generate({"coverage" => blob})
            yield payload.bytesize if block_given?
            File.write(path, payload)
            path
          end
          Polyrun::Coverage::Merge.merge_files(paths)
        end
      end

      def cooker_paths(files)
        @cooker_paths ||= {}
        @cooker_paths[files] ||= Array.new(files) { |fi| -"/m/#{fi}.rb" }.freeze
      end

      def build_blob(rng, files, lines, offset)
        h = {}
        paths = cooker_paths(files)
        files.times do |fi|
          path = paths[fi]
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

      def env_int(name, default)
        Integer(ENV.fetch(name, default.to_s))
      end
    end
  end
end

Polyrun::Bench::CookerRun.run! if $PROGRAM_NAME == __FILE__
