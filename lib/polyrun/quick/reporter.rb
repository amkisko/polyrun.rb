module Polyrun
  module Quick
    class Reporter
      SLOW_THRESHOLD_SECONDS = 0.05
      SLOWEST_LIMIT = 5

      def initialize(out, err, verbose)
        @out = out
        @err = err
        @verbose = verbose
        @passed = 0
        @failed = 0
        @errors = 0
        @timings = []
      end

      def pass(group, description, duration_seconds: nil)
        @passed += 1
        record_timing(group, description, duration_seconds)
        return unless @verbose

        @out.puts "  ok  #{group} #{description}#{duration_suffix(duration_seconds)}"
      end

      def fail(group, description, exc, duration_seconds: nil)
        @failed += 1
        record_timing(group, description, duration_seconds)
        @err.puts "  FAIL  #{group} #{description}#{duration_suffix(duration_seconds)}"
        @err.puts "         #{exc.message}"
      end

      def error(group, description, exc, duration_seconds: nil)
        @errors += 1
        record_timing(group, description, duration_seconds)
        @err.puts "  ERROR #{group} #{description}#{duration_suffix(duration_seconds)}"
        @err.puts "         #{exc.class}: #{exc.message}"
        loc = exc.backtrace&.first
        @err.puts "         #{loc}" if loc
      end

      def summary
        total = @passed + @failed + @errors
        @out.puts
        @out.puts "Polyrun::Quick: #{@passed} passed, #{@failed} failed, #{@errors} errors (#{total} examples)"
        print_slowest!
        (@failed + @errors).positive? ? 1 : 0
      end

      private

      def record_timing(group, description, duration_seconds)
        return if duration_seconds.nil?

        @timings << ["#{group} #{description}".strip, duration_seconds.to_f]
      end

      def duration_suffix(duration_seconds)
        return "" if duration_seconds.nil?

        format(" (%.3fs)", duration_seconds)
      end

      def print_slowest!
        slow = @timings.select { |(_, sec)| sec >= SLOW_THRESHOLD_SECONDS }
          .sort_by { |(_, sec)| -sec }
          .first(SLOWEST_LIMIT)
        return if slow.empty?

        @out.puts "Slowest:"
        slow.each do |label, sec|
          @out.puts format("  %.3fs  %s", sec, label)
        end
      end
    end
  end
end
