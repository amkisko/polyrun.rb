# frozen_string_literal: true

require "fileutils"
require "json"
require "socket"
require_relative "pressure/process_sample"

module Polyrun
  module Benchmark
    # Process resource sampler for pressure / load benches.
    #
    # Measures wall time, CPU (user+system), RSS, GC / heap, optional storage and
    # network byte counters. Callers raise load (N, threads, payload size) and lower
    # resource targets after each successful round.
    #
    # Usage:
    #   result = Polyrun::Benchmark::Pressure.measure(label: "merge_disk", ops: 8) do
    #     merge_files(...)
    #   end
    #   Polyrun::Benchmark::Pressure.write_results!([result], repository_root: Dir.pwd)
    module Pressure
      module_function

      DEFAULT_TARGET_FACTOR = 0.85

      def sample
        ProcessSample.sample
      end

      def diff(before, after_sample, extras: {})
        ProcessSample.diff(before, after_sample, extras: extras)
      end

      def measure(label:, ops: nil, gc_start: true, extras: {})
        GC.start if gc_start
        before = sample
        started = ProcessSample.monotonic_s
        yield
        wall_s = ProcessSample.monotonic_s - started
        after_sample = sample
        metrics = diff(before, after_sample, extras: extras)
        metrics["wall_s"] = wall_s
        metrics["cpu_pct"] = wall_s.positive? ? (metrics["cpu_s"] / wall_s) * 100.0 : 0.0
        result = {
          "label" => label.to_s,
          "ops" => ops,
          "ops_per_s" => (ops && wall_s.positive?) ? ops / wall_s : nil,
          "metrics" => metrics,
          "targets" => extras["targets"],
          "pass" => targets_met?(metrics, extras["targets"])
        }
        result["report"] = format_report(result)
        result
      end

      def targets_from(metrics, factor: DEFAULT_TARGET_FACTOR)
        {
          "wall_s" => metrics["wall_s"] * factor,
          "cpu_s" => metrics["cpu_s"] * factor,
          "rss_delta_bytes" => [metrics["rss_delta_bytes"] * factor, 0].max,
          "heap_delta_bytes" => [metrics["heap_delta_bytes"] * factor, 0].max,
          "storage_delta_bytes" => [metrics["storage_delta_bytes"] * factor, 0].max,
          "network_in_bytes" => metrics["network_in_bytes"] * factor,
          "network_out_bytes" => metrics["network_out_bytes"] * factor
        }
      end

      def targets_met?(metrics, targets)
        return nil if targets.nil? || targets.empty?

        targets.all? do |key, limit|
          next true if limit.nil?
          next true unless metrics.key?(key)

          metrics[key].to_f <= limit.to_f
        end
      end

      def format_report(result)
        m = result["metrics"]
        parts = format_report_core(result, m)
        append_format_report_extras!(parts, result, m)
        parts.join(" | ")
      end

      def write_results!(results, repository_root: Dir.pwd, name: "load")
        dir = File.join(repository_root, "benchmarks", "output")
        FileUtils.mkdir_p(dir)
        stamp = Time.now.utc.strftime("%Y%m%d%H%M%S")
        path = File.join(dir, "#{stamp}_#{name}.json")
        payload = {
          "meta" => {
            "recorded_at" => Time.now.utc.iso8601,
            "ruby" => RUBY_VERSION,
            "engine" => RUBY_ENGINE,
            "platform" => RUBY_PLATFORM,
            "polyrun_version" => defined?(Polyrun::VERSION) ? Polyrun::VERSION : nil,
            "hostname" => Socket.gethostname
          },
          "results" => results
        }
        File.write(path, JSON.pretty_generate(payload))
        path
      end

      def human_bytes(value)
        n = value.to_f
        units = %w[B KiB MiB GiB]
        i = 0
        while n.abs >= 1024.0 && i < units.length - 1
          n /= 1024.0
          i += 1
        end
        format("%.1f%s", n, units[i])
      end

      def format_report_core(result, metrics)
        [
          result["label"],
          format("wall=%.4fs", metrics["wall_s"]),
          format("cpu=%.4fs (%.0f%%)", metrics["cpu_s"], metrics["cpu_pct"]),
          format("rss=%s (Δ%s)", human_bytes(metrics["rss_bytes"]), human_bytes(metrics["rss_delta_bytes"])),
          format("heap_Δ=%s", human_bytes(metrics["heap_delta_bytes"])),
          format("alloc=%d", metrics.dig("gc", "allocated_objects") || 0)
        ]
      end

      def append_format_report_extras!(parts, result, metrics)
        parts << format("ops/s=%.1f", result["ops_per_s"]) if result["ops_per_s"]
        if metrics["storage_delta_bytes"].to_i != 0
          parts << format("storage_Δ=%s", human_bytes(metrics["storage_delta_bytes"]))
        end
        net = metrics["network_in_bytes"].to_i + metrics["network_out_bytes"].to_i
        parts << format("net=%s", human_bytes(net)) if net != 0
        return if result["pass"].nil?

        parts << (result["pass"] ? "PASS" : "FAIL targets")
      end
      private_class_method :format_report_core, :append_format_report_extras!
    end
  end
end

require_relative "pressure/cooker"
