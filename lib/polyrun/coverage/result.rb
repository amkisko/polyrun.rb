module Polyrun
  module Coverage
    # Payload passed to formatters (SimpleCov-compatible): merged line coverage plus JSON meta/groups.
    class Result
      attr_reader :coverage_blob, :meta, :groups

      def initialize(coverage_blob, meta: {}, groups: nil)
        @coverage_blob = coverage_blob
        @meta = meta.is_a?(Hash) ? meta : {}
        @groups = groups
      end

      def files
        coverage_blob.keys
      end
    end
  end
end
