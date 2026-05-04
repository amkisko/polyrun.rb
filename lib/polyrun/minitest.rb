require_relative "../polyrun"

module Polyrun
  # Optional Minitest-oriented wiring (require +polyrun/minitest+ explicitly).
  #
  # Does not load the +minitest+ gem. Call {install_parallel_provisioning!} from +test/test_helper.rb+
  # after Rails / DB configuration (same timing as a direct call to
  # {Data::ParallelProvisioning.run_suite_hooks!}).
  module Minitest
    module WorkerPingTestHook
      def setup
        Polyrun::WorkerPing.ping!(location: polyrun_minitest_location)
        super
      end

      def teardown
        super
        Polyrun::WorkerPing.ping!(location: polyrun_minitest_location)
      end

      private

      def polyrun_minitest_location
        file, line = method(name).source_location
        (file && line) ? "#{file}:#{line}" : nil
      rescue NameError
        nil
      end
    end

    module_function

    # Runs {Data::ParallelProvisioning.run_suite_hooks!} (serial vs shard worker hooks).
    def install_parallel_provisioning!
      Polyrun::Data::ParallelProvisioning.run_suite_hooks!
    end

    # Same ping semantics as {RSpec.install_worker_ping!}: +ping!+ at test +setup+ and +teardown+.
    # Requires +minitest+ to be loaded first (+Minitest::Test+ defined).
    def install_worker_ping!
      require_relative "worker_ping"
      unless defined?(::Minitest::Test)
        Polyrun::Log.warn "polyrun minitest: install_worker_ping! skipped (load minitest/autorun or minitest/test first)"
        return
      end

      ::Minitest::Test.send(:prepend, WorkerPingTestHook)
      Polyrun::WorkerPing.ensure_interval_ping_thread!
    end
  end
end
