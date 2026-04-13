module Polyrun
  module Timing
    # Human-readable slow-file list from merged timing JSON (per-file cost).
    module Summary
      module_function

      # +merged+ is path (String) => seconds (Float), as produced by +Timing::Merge.merge_files+.
      def format_slow_files(merged, top: 30, title: "Polyrun slowest files (by wall time, seconds)")
        return "#{title}\n  (no data)\n" if merged.nil? || merged.empty?

        pairs = merged.sort_by { |_, sec| -sec.to_f }.first(Integer(top))
        lines = [title, ""]
        pairs.each_with_index do |(path, sec), i|
          lines << format("  %2d. %s  %.4f", i + 1, path, sec.to_f)
        end
        lines.join("\n") + "\n"
      end

      def write_file(merged, path, **kwargs)
        File.write(path, format_slow_files(merged, **kwargs))
        path
      end
    end
  end
end
