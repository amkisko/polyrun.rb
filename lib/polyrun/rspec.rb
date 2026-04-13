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
  end
end
