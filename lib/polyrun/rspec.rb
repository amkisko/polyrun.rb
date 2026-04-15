require_relative "../polyrun"

module Polyrun
  # Optional RSpec wiring (require +polyrun/rspec+ explicitly).
  module RSpec
    module_function

    # Registers +before(:suite)+ to run {Data::ParallelProvisioning.run_suite_hooks!}.
    def install_parallel_provisioning!(rspec_config)
      rspec_config.before(:suite) do
        Polyrun::Data::ParallelProvisioning.run_suite_hooks!
      end
    end

    # Experimental: add {Timing::RSpecExampleFormatter} and write per-example JSON (see +timing_granularity: example+).
    # With +output_path:+, that path is used directly (no +ENV+ mutation). Without it, the formatter
    # reads +ENV["POLYRUN_EXAMPLE_TIMING_OUT"]+ or defaults to +polyrun_timing_examples.json+.
    def install_example_timing!(output_path: nil)
      require_relative "timing/rspec_example_formatter"
      fmt =
        if output_path
          op = output_path
          Class.new(Polyrun::Timing::RSpecExampleFormatter) do
            define_method(:timing_output_path) { op }
          end
        else
          Polyrun::Timing::RSpecExampleFormatter
        end
      ::RSpec.configure do |config|
        config.add_formatter fmt
      end
    end
  end
end
