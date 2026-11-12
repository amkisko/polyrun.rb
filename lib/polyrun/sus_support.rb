require_relative "../polyrun"

module Polyrun
  # Optional Sus-oriented wiring (require +polyrun/sus_support+ explicitly).
  #
  # Does not load the +sus+ gem. Call installers from +config/sus.rb+ after Sus is available
  # when a hook needs +Sus::Config+.
  module SusSupport
    module WorkerPingConfigHook
      def before_tests(assertions, output: self.output)
        Polyrun::WorkerPing.ping!(location: "sus:before_tests")
        super
      end

      def after_tests(assertions, output: self.output)
        super
        Polyrun::WorkerPing.ping!(location: "sus:after_tests")
      end
    end

    module_function

    # Runs {Data::ParallelProvisioning.run_suite_hooks!} (serial vs shard worker hooks).
    def install_parallel_provisioning!
      Polyrun::Data::ParallelProvisioning.run_suite_hooks!
    end

    # Start {Coverage::Collector} when Polyrun or Covered coverage env is on.
    # Prefer this for shard fragment merge. If Covered::Sus is already included on +Sus::Config+,
    # skip starting the collector so +Coverage.start+ is not contested in one process.
    def install_coverage!(root: Dir.pwd, **kwargs)
      require_relative "coverage/collector"
      return unless Polyrun::Coverage::Collector.coverage_requested_for_quick?(root)

      if defined?(::Covered::Sus) && defined?(::Sus::Config) && ::Sus::Config.ancestors.include?(::Covered::Sus)
        Polyrun::Log.warn "polyrun sus_support: install_coverage! skipped (Covered::Sus already on Sus::Config; use one coverage collector per process)"
        return
      end

      Polyrun::Coverage::Collector.start!(root: root, **kwargs)
    end

    # Ping at Sus +before_tests+ / +after_tests+ when +Sus::Config+ is defined.
    def install_worker_ping!
      require_relative "worker_ping"
      unless defined?(::Sus::Config)
        Polyrun::Log.warn "polyrun sus_support: install_worker_ping! skipped (load Sus before calling)"
        return
      end

      ::Sus::Config.prepend(WorkerPingConfigHook)
      Polyrun::WorkerPing.ensure_interval_ping_thread!
    end
  end
end
