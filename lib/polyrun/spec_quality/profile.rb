module Polyrun
  module SpecQuality
    # Stdlib per-example CPU / allocation / IO snapshots.
    module Profile
      module_function

      def snapshot
        cpu = Process.times
        gc = GC.stat
        io = read_proc_io
        {
          "cpu_user" => cpu.utime,
          "cpu_system" => cpu.stime,
          "gc_allocated" => gc[:total_allocated_objects],
          "gc_heap_live" => gc[:heap_live_slots],
          "io_read_bytes" => io[:read_bytes],
          "io_write_bytes" => io[:write_bytes]
        }
      end

      def diff(before, after)
        before ||= {}
        after ||= {}
        out = {}
        %w[cpu_user cpu_system gc_allocated gc_heap_live io_read_bytes io_write_bytes].each do |k|
          b = before[k]
          a = after[k]
          next if b.nil? && a.nil?

          delta = numeric(a) - numeric(b)
          out[k] = delta if delta.positive? || k.start_with?("cpu")
          out[k] = delta
        end
        out
      end

      def enabled_dimensions(profile_list)
        Array(profile_list).map(&:to_s).map(&:downcase)
      end

      def slice_profile(diff, dimensions)
        dims = enabled_dimensions(dimensions)
        return diff if dims.empty?

        out = {}
        out["wall"] = diff["wall"] if diff.key?("wall") && dims.include?("wall")
        if dims.include?("cpu")
          out["cpu_user"] = diff["cpu_user"] if diff.key?("cpu_user")
          out["cpu_system"] = diff["cpu_system"] if diff.key?("cpu_system")
        end
        if dims.include?("mem")
          out["gc_allocated"] = diff["gc_allocated"] if diff.key?("gc_allocated")
          out["gc_heap_live"] = diff["gc_heap_live"] if diff.key?("gc_heap_live")
        end
        if dims.include?("io")
          out["io_read_bytes"] = diff["io_read_bytes"] if diff.key?("io_read_bytes")
          out["io_write_bytes"] = diff["io_write_bytes"] if diff.key?("io_write_bytes")
        end
        out
      end

      def read_proc_io
        path = "/proc/self/io"
        return {read_bytes: nil, write_bytes: nil} unless File.readable?(path)

        read_bytes = nil
        write_bytes = nil
        File.foreach(path) do |line|
          case line
          when /\Aread_bytes:\s+(\d+)/
            read_bytes = Regexp.last_match(1).to_i
          when /\Awrite_bytes:\s+(\d+)/
            write_bytes = Regexp.last_match(1).to_i
          end
        end
        {read_bytes: read_bytes, write_bytes: write_bytes}
      rescue SystemCallError
        {read_bytes: nil, write_bytes: nil}
      end

      def numeric(value)
        return 0 if value.nil?

        value.is_a?(Numeric) ? value : value.to_f
      end
      private_class_method :numeric
    end
  end
end
