# frozen_string_literal: true

require "objspace"
require "open3"

module Polyrun
  module Benchmark
    module Pressure
      # Wall/CPU/RSS/heap/GC sampling and diffs for {Pressure.measure}.
      module ProcessSample
        module_function

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
          cpu = cpu_diff(before, after_sample)
          memory = memory_diff(before, after_sample)
          io = io_diff(before, after_sample, extras)
          {
            "wall_s" => wall_s,
            "cpu_user_s" => cpu[:user],
            "cpu_system_s" => cpu[:system],
            "cpu_s" => cpu[:total],
            "cpu_pct" => wall_s.positive? ? (cpu[:total] / wall_s) * 100.0 : 0.0,
            "rss_bytes" => memory[:rss],
            "rss_delta_bytes" => memory[:rss_delta],
            "heap_bytes" => memory[:heap],
            "heap_delta_bytes" => memory[:heap_delta],
            "gc" => gc_diff(before["gc"], after_sample["gc"]),
            "storage_delta_bytes" => io[:storage],
            "network_in_bytes" => io[:network_in],
            "network_out_bytes" => io[:network_out]
          }
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

        def cpu_diff(before, after_sample)
          user = after_sample["cpu_user_s"] - before["cpu_user_s"]
          system = after_sample["cpu_system_s"] - before["cpu_system_s"]
          {user: user, system: system, total: user + system}
        end

        def memory_diff(before, after_sample)
          {
            rss: after_sample["rss_bytes"],
            rss_delta: after_sample["rss_bytes"] - before["rss_bytes"],
            heap: after_sample["heap_bytes"],
            heap_delta: after_sample["heap_bytes"] - before["heap_bytes"]
          }
        end

        def io_diff(before, after_sample, extras)
          {
            storage: (after_sample["storage_bytes"] - before["storage_bytes"]) +
              extras.fetch("storage_delta_bytes", 0),
            network_in: (after_sample["network_in_bytes"] - before["network_in_bytes"]) +
              extras.fetch("network_in_bytes", 0),
            network_out: (after_sample["network_out_bytes"] - before["network_out_bytes"]) +
              extras.fetch("network_out_bytes", 0)
          }
        end
      end
    end
  end
end
