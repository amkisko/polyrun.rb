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

    # Per-worker failure JSONL fragments for +polyrun run-shards --merge-failures+ (parity with coverage shards).
    # Requires +POLYRUN_FAILURE_FRAGMENTS=1+ (set by the parent when --merge-failures is used) unless +only_if+ overrides.
    # Writes +tmp/polyrun_failures/polyrun-failure-fragment-*.jsonl+ (override dir with +POLYRUN_FAILURE_FRAGMENT_DIR+).
    def install_failure_fragments!(only_if: nil)
      pred = only_if || -> { %w[1 true yes].include?(ENV["POLYRUN_FAILURE_FRAGMENTS"].to_s.downcase) }
      return unless pred.call

      require "rspec/core"
      require_relative "reporting/rspec_failure_fragment_formatter"
      ::RSpec.configure do |config|
        config.add_formatter Polyrun::Reporting::RspecFailureFragmentFormatter
      end
    end

    # Writes {WorkerPing} after suite start, before/after each example (+location+ is file:line from metadata).
    # Keeps +--worker-idle-timeout+ sensitive to example progress (not only a background thread).
    def install_worker_ping!
      require "rspec/core"
      require_relative "worker_ping"
      ::RSpec.configure do |config|
        config.before(:suite) { Polyrun::WorkerPing.ping! }
        config.before(:each) do |example|
          Polyrun::WorkerPing.ping!(location: example.metadata[:location] || example.location)
        end
        config.after(:each) do |example|
          Polyrun::WorkerPing.ping!(location: example.metadata[:location] || example.location)
        end
      end

      Polyrun::WorkerPing.ensure_interval_ping_thread!
    end
  end
end
