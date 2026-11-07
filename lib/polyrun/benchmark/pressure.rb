# frozen_string_literal: true

require "fileutils"
require "json"
require "objspace"
require "open3"
require "socket"

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
        times = Process.times
        {
          "wall_s" => monotonic_s,
          "cpu_user_s" => times.utime,
          "cpu_system_s" => times.stime,
          "rss_bytes" => rss_bytes,
          "heap_bytes" => heap_bytes,
          "gc" => gc_sample,
          "storage_bytes" => 0,
          "network_in_bytes" => 0,
          "network_out_bytes" => 0
        }
      end

      def diff(before, after_sample, extras: {})
        wall_s = after_sample["wall_s"] - before["wall_s"]
        cpu_user = after_sample["cpu_user_s"] - before["cpu_user_s"]
        cpu_system = after_sample["cpu_system_s"] - before["cpu_system_s"]
        cpu_s = cpu_user + cpu_system
        {
          "wall_s" => wall_s,
          "cpu_user_s" => cpu_user,
          "cpu_system_s" => cpu_system,
          "cpu_s" => cpu_s,
          "cpu_pct" => wall_s.positive? ? (cpu_s / wall_s) * 100.0 : 0.0,
          "rss_bytes" => after_sample["rss_bytes"],
          "rss_delta_bytes" => after_sample["rss_bytes"] - before["rss_bytes"],
          "heap_bytes" => after_sample["heap_bytes"],
          "heap_delta_bytes" => after_sample["heap_bytes"] - before["heap_bytes"],
          "gc" => gc_diff(before["gc"], after_sample["gc"]),
          "storage_delta_bytes" =>
            (after_sample["storage_bytes"] - before["storage_bytes"]) + extras.fetch("storage_delta_bytes", 0),
          "network_in_bytes" =>
            (after_sample["network_in_bytes"] - before["network_in_bytes"]) + extras.fetch("network_in_bytes", 0),
          "network_out_bytes" =>
            (after_sample["network_out_bytes"] - before["network_out_bytes"]) + extras.fetch("network_out_bytes", 0)
        }
      end

      def measure(label:, ops: nil, gc_start: true, extras: {})
        GC.start if gc_start
        before = sample
        started = monotonic_s
        yield
        wall_s = monotonic_s - started
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
        parts = [
          result["label"],
          format("wall=%.4fs", m["wall_s"]),
          format("cpu=%.4fs (%.0f%%)", m["cpu_s"], m["cpu_pct"]),
          format("rss=%s (Δ%s)", human_bytes(m["rss_bytes"]), human_bytes(m["rss_delta_bytes"])),
          format("heap_Δ=%s", human_bytes(m["heap_delta_bytes"])),
          format("alloc=%d", m.dig("gc", "allocated_objects") || 0)
        ]
        parts << format("ops/s=%.1f", result["ops_per_s"]) if result["ops_per_s"]
        if m["storage_delta_bytes"].to_i != 0
          parts << format("storage_Δ=%s", human_bytes(m["storage_delta_bytes"]))
        end
        net = m["network_in_bytes"].to_i + m["network_out_bytes"].to_i
        parts << format("net=%s", human_bytes(net)) if net != 0
        unless result["pass"].nil?
          parts << (result["pass"] ? "PASS" : "FAIL targets")
        end
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

      def monotonic_s
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def rss_bytes
        if File.readable?("/proc/self/status")
          status = File.read("/proc/self/status")
          if (match = status.match(/^VmRSS:\s+(\d+)\s+kB/))
            return match[1].to_i * 1024
          end
        end

        stdout, status = Open3.capture2("ps", "-o", "rss=", "-p", Process.pid.to_s)
        return 0 unless status.success?

        stdout.strip.to_i * 1024
      rescue
        0
      end

      def heap_bytes
        ObjectSpace.memsize_of_all
      rescue
        0
      end

      def gc_sample
        stat = GC.stat
        {
          "count" => stat[:count],
          "allocated_objects" => stat[:total_allocated_objects],
          "heap_live_slots" => stat[:heap_live_slots],
          "heap_free_slots" => stat[:heap_free_slots],
          "major_gc_count" => stat[:major_gc_count],
          "minor_gc_count" => stat[:minor_gc_count]
        }
      end

      def gc_diff(before, after_sample)
        {
          "count" => after_sample["count"] - before["count"],
          "allocated_objects" => after_sample["allocated_objects"] - before["allocated_objects"],
          "heap_live_slots" => after_sample["heap_live_slots"],
          "heap_live_delta" => after_sample["heap_live_slots"] - before["heap_live_slots"],
          "major_gc_count" => after_sample["major_gc_count"] - before["major_gc_count"],
          "minor_gc_count" => after_sample["minor_gc_count"] - before["minor_gc_count"]
        }
      end
    end
  end
end

require_relative "pressure/cooker"
