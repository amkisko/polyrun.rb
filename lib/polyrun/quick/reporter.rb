module Polyrun
  module Quick
    class Reporter
      def initialize(out, err, verbose)
        @out = out
        @err = err
        @verbose = verbose
        @passed = 0
        @failed = 0
        @errors = 0
      end

      def pass(group, description)
        @passed += 1
        return unless @verbose

        @out.puts "  ok  #{group} #{description}"
      end

      def fail(group, description, exc)
        @failed += 1
        @err.puts "  FAIL  #{group} #{description}"
        @err.puts "         #{exc.message}"
      end

      def error(group, description, exc)
        @errors += 1
        @err.puts "  ERROR #{group} #{description}"
        @err.puts "         #{exc.class}: #{exc.message}"
        loc = exc.backtrace&.first
        @err.puts "         #{loc}" if loc
      end

      def summary
        total = @passed + @failed + @errors
        @out.puts
        @out.puts "Polyrun::Quick: #{@passed} passed, #{@failed} failed, #{@errors} errors (#{total} examples)"
        (@failed + @errors).positive? ? 1 : 0
      end
    end
  end
end
