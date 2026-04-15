require "json"

require "rspec/core/formatters/base_formatter"

module Polyrun
  module Timing
    # Experimental: records +absolute_path:line_number+ => wall seconds per example for
    # {Partition::Plan} +timing_granularity: :example+ and +merge-timing+.
    #
    # Use after RSpec is loaded:
    #   require "polyrun/timing/rspec_example_formatter"
    #   RSpec.configure { |c| c.add_formatter Polyrun::Timing::RSpecExampleFormatter }
    # Or {Polyrun::RSpec.install_example_timing!} (+output_path:+ avoids touching +ENV+).
    #
    # Default output path: +ENV["POLYRUN_EXAMPLE_TIMING_OUT"]+ if set, else +polyrun_timing_examples.json+.
    class RSpecExampleFormatter < RSpec::Core::Formatters::BaseFormatter
      RSpec::Core::Formatters.register self, :example_finished, :close

      def initialize(output)
        super
        @times = {}
      end

      def example_finished(notification)
        ex = notification.example
        result = ex.execution_result
        return if result.pending?

        t = result.run_time
        return unless t

        path = ex.metadata[:absolute_path]
        return unless path

        line = ex.metadata[:line_number]
        return unless line

        key = "#{File.expand_path(path)}:#{line}"
        cur = @times[key]
        @times[key] = cur ? [cur, t].max : t
      end

      def close(_notification)
        File.write(timing_output_path, JSON.pretty_generate(@times))
      end

      # Override in a subclass from {Polyrun::RSpec.install_example_timing!(output_path: ...)}.
      def timing_output_path
        ENV["POLYRUN_EXAMPLE_TIMING_OUT"] || "polyrun_timing_examples.json"
      end
    end
  end
end
