# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module Polyrun
  module Benchmark
    module Pressure
      # Episode helpers for amkisko/pressure-benchmarking prayer: multi-sample measure,
      # propose ceilings, calibrate stage separation, and cooker iteration logs.
      module Cooker
        DEFAULT_SAMPLES = 3
        DEFAULT_HEADROOM = 1.15
        DEFAULT_COOKER_N = 10
        SERIES_KEYS = %w[
          wall_s cpu_s rss_delta_bytes heap_delta_bytes storage_delta_bytes
          network_in_bytes network_out_bytes allocated_objects
        ].freeze

        module_function

        def measure_samples(n:, label:, ops: nil, gc_start: true, extras: {}, &block)
          raise ArgumentError, "samples-per-load must be >= 1" if n < 1

          samples = Array.new(n) do |i|
            Pressure.measure(
              label: "#{label}_s#{i + 1}",
              ops: ops,
              gc_start: gc_start,
              extras: extras,
              &block
            )
          end
          aggregate(samples, label: label, basis: extras.fetch("basis", "median"))
        end

        def aggregate(samples, label:, basis: "median")
          metrics_list = samples.map { |s| flatten_metrics(s["metrics"]) }
          keys = SERIES_KEYS
          summary = {}
          keys.each do |key|
            values = metrics_list.filter_map { |m| m[key] }
            next if values.empty?

            summary[key] = {
              "samples" => values,
              "median" => percentile(values, 0.5),
              "max" => values.max,
              "min" => values.min,
              "basis_value" => (basis.to_s == "max") ? values.max : percentile(values, 0.5)
            }
          end
          wall = summary.dig("wall_s", "basis_value")
          ops = samples.first && samples.first["ops"]
          {
            "label" => label.to_s,
            "ops" => ops,
            "ops_per_s" => (ops && wall && wall.positive?) ? ops / wall : nil,
            "basis" => basis.to_s,
            "n" => samples.length,
            "samples" => samples,
            "series" => summary,
            "metrics" => summary.transform_values { |h| h["basis_value"] },
            "gateable" => samples.length >= DEFAULT_SAMPLES
          }
        end

        def flatten_metrics(metrics)
          flat = metrics.dup
          flat["allocated_objects"] = metrics.dig("gc", "allocated_objects")
          flat
        end

        def propose_ceilings(series_summary, headroom: DEFAULT_HEADROOM, keys: nil)
          keys ||= SERIES_KEYS
          keys.each_with_object({}) do |key, out|
            entry = series_summary[key] || series_summary.dig("series", key)
            next unless entry

            value = entry.is_a?(Hash) ? entry["basis_value"] : entry
            next if value.nil?

            out[key] = value.to_f * headroom
          end
        end

        def gate(series_or_metrics, ceilings)
          metrics = series_or_metrics["metrics"] || series_or_metrics
          failures = []
          ceilings.each do |key, limit|
            next if limit.nil?
            next unless metrics.key?(key)

            failures << key if metrics[key].to_f > limit.to_f
          end
          {"pass" => failures.empty?, "failures" => failures, "metrics" => metrics, "ceilings" => ceilings}
        end

        def calibrate!(stages)
          # stages: ordered Array of [name, known_rank, callable]
          # known_rank must be strictly increasing with expected wall cost.
          measured = stages.map do |name, known_rank, callable|
            result = Pressure.measure(label: "calibrate_#{name}", ops: 1, gc_start: true) { callable.call }
            {
              "stage" => name.to_s,
              "known_rank" => known_rank,
              "wall_s" => result["metrics"]["wall_s"],
              "cpu_s" => result["metrics"]["cpu_s"]
            }
          end
          by_wall = measured.sort_by { |row| row["wall_s"] }
          by_known = measured.sort_by { |row| row["known_rank"] }
          order_ok = by_wall.map { |r| r["stage"] } == by_known.map { |r| r["stage"] }
          distinct = measured.map { |r| r["wall_s"] }.uniq.length == measured.length
          {
            "pass" => order_ok && distinct,
            "order_ok" => order_ok,
            "distinct_wall" => distinct,
            "stages" => measured,
            "report" => format_calibrate(measured, order_ok, distinct)
          }
        end

        def format_calibrate(measured, order_ok, distinct)
          lines = measured.map { |r| format("%s rank=%s wall=%.6fs cpu=%.6fs", r["stage"], r["known_rank"], r["wall_s"], r["cpu_s"]) }
          status = (order_ok && distinct) ? "PASS" : "FAIL"
          ([status, "order_ok=#{order_ok}", "distinct_wall=#{distinct}"] + lines).join(" | ")
        end

        def load_ceilings(path)
          return {} unless File.file?(path)

          JSON.parse(File.read(path))
        end

        def write_ceilings!(path, ceilings, meta: {})
          FileUtils.mkdir_p(File.dirname(path))
          payload = {
            "meta" => meta.merge("recorded_at" => Time.now.utc.iso8601),
            "ceilings" => ceilings
          }
          File.write(path, JSON.pretty_generate(payload))
          path
        end

        def new_episode(repository_root:, binding:)
          {
            "started_at" => Time.now.utc.iso8601,
            "finished_at" => nil,
            "repository_root" => repository_root,
            "binding" => binding,
            "calibrate" => nil,
            "load_steps" => [],
            "ceilings_before" => nil,
            "ceilings_after" => nil,
            "iterations" => [],
            "accepted" => false,
            "stop_reason" => nil
          }
        end

        def append_iteration!(episode, iteration:, primary:, hypothesis:, change:, prove:)
          episode["iterations"] << {
            "n" => iteration,
            "primary_series" => primary,
            "hypothesis" => hypothesis,
            "change" => change,
            "prove" => prove
          }
          episode
        end

        def write_episode!(episode, path:)
          episode["finished_at"] = Time.now.utc.iso8601
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, JSON.pretty_generate(episode))
          path
        end

        def percentile(values, fraction)
          sorted = values.map(&:to_f).sort
          return sorted.first if sorted.length == 1

          idx = ((sorted.length - 1) * fraction).round
          sorted[idx]
        end
      end
    end
  end
end
