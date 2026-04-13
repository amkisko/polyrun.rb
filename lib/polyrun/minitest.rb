require_relative "../polyrun"

module Polyrun
  # Optional Minitest-oriented wiring (require +polyrun/minitest+ explicitly).
  #
  # Does not load the +minitest+ gem. Call {install_parallel_provisioning!} from +test/test_helper.rb+
  # after Rails / DB configuration (same timing as a direct call to
  # {Data::ParallelProvisioning.run_suite_hooks!}).
  module Minitest
    module_function

    # Runs {Data::ParallelProvisioning.run_suite_hooks!} (serial vs shard worker hooks).
    def install_parallel_provisioning!
      Polyrun::Data::ParallelProvisioning.run_suite_hooks!
    end
  end
end
