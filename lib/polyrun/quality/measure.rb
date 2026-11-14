require_relative "command"
require_relative "../benchmark/pressure/process_sample"

module Polyrun
  module Quality
    module Measure
      module_function

      def call(command, root:, timeout:, label:, ceilings: {}, max_output: Command::DEFAULT_OUTPUT_LIMIT)
        validate_ceilings!(ceilings)
        before = Process.times
        result = Command.call(command, root: root, timeout: timeout, max_output: max_output)
        metrics = process_metrics(before).merge("wall_s" => result["wall_s"])
        failures = ceilings.keys.select { |key| !metrics[key].is_a?(Numeric) || metrics[key] > ceilings[key] }
        result.merge("ok" => result["exitstatus"].zero? && failures.empty?, "label" => label, "metrics" => metrics,
          "failures" => failures, "memory_probe_class" => "orchestrator_sample", "network" => "not_measured", "energy_proxy" => "cpu_seconds")
      end

      def process_metrics(before)
        after = Process.times
        rss = Benchmark::Pressure::ProcessSample.rss_bytes
        {
          "cpu_s" => after.utime + after.stime - before.utime - before.stime,
          "child_cpu_s" => after.cutime + after.cstime - before.cutime - before.cstime,
          "orchestrator_rss_bytes" => rss.positive? ? rss : nil
        }
      end

      def validate_ceilings!(ceilings)
        raise ArgumentError, "ceilings must be an object" unless ceilings.is_a?(Hash)
        unless ceilings.values.all? { |value| value.is_a?(Numeric) && value.finite? && value >= 0 }
          raise ArgumentError, "ceilings must be finite nonnegative numbers"
        end
      end
      private_class_method :process_metrics, :validate_ceilings!
    end
  end
end
