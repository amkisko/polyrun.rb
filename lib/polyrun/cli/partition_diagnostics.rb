module Polyrun
  class CLI
    # Shared stderr diagnostics after {Partition::Plan} is built.
    module PartitionDiagnostics
      private

      def partition_emit_diagnostics!(plan:, items:, costs:, timing_path:, granularity: :file)
        return unless timing_path && costs && !costs.empty?

        analysis = Polyrun::Partition::TimingDiagnostics.analyze(
          items: items,
          costs: costs,
          timing_path: timing_path,
          root: plan.root,
          granularity: granularity
        )
        Polyrun::Partition::TimingDiagnostics.emit_warnings!(analysis)
        Polyrun::Partition::Reports.emit_all!(plan)
      end
    end
  end
end
