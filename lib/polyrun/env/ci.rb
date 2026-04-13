module Polyrun
  module Env
    # CI-native shard index/total (spec2 §6.4) without extra gems.
    module Ci
      module_function

      # Returns Integer shard index or nil if not inferable from CI env.
      def detect_shard_index
        return Integer(ENV["POLYRUN_SHARD_INDEX"]) if present?(ENV["POLYRUN_SHARD_INDEX"])

        ci = truthy?(ENV["CI"])
        if present?(ENV["CI_NODE_INDEX"]) && ci
          return Integer(ENV["CI_NODE_INDEX"])
        end
        if present?(ENV["BUILDKITE_PARALLEL_JOB"]) && ci
          return Integer(ENV["BUILDKITE_PARALLEL_JOB"])
        end
        if present?(ENV["CIRCLE_NODE_INDEX"]) && ci
          return Integer(ENV["CIRCLE_NODE_INDEX"])
        end

        nil
      rescue ArgumentError, TypeError
        nil
      end

      # Returns Integer shard total or nil.
      def detect_shard_total
        return Integer(ENV["POLYRUN_SHARD_TOTAL"]) if present?(ENV["POLYRUN_SHARD_TOTAL"])

        ci = truthy?(ENV["CI"])
        if present?(ENV["CI_NODE_TOTAL"]) && ci
          return Integer(ENV["CI_NODE_TOTAL"])
        end
        if present?(ENV["BUILDKITE_PARALLEL_JOB_COUNT"]) && ci
          return Integer(ENV["BUILDKITE_PARALLEL_JOB_COUNT"])
        end
        if present?(ENV["CIRCLE_NODE_TOTAL"]) && ci
          return Integer(ENV["CIRCLE_NODE_TOTAL"])
        end

        nil
      rescue ArgumentError, TypeError
        nil
      end

      def polyrun_env
        e = ENV["POLYRUN_ENV"]&.strip
        return e if present?(e)

        return "ci" if truthy?(ENV["CI"])

        "local"
      end

      def present?(s)
        !s.nil? && !s.to_s.empty?
      end

      def truthy?(s)
        %w[1 true yes].include?(s.to_s.downcase)
      end
    end
  end
end
