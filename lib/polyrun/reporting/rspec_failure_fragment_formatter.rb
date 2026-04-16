require "json"
require "fileutils"

module Polyrun
  module Reporting
    # RSpec formatter: appends one JSON object per failed example to the shard fragment file.
    # Enable via +Polyrun::RSpec.install_failure_fragments!+ and +POLYRUN_FAILURE_FRAGMENTS=1+ (set by run-shards --merge-failures).
    #
    # Output: +tmp/polyrun_failures/polyrun-failure-fragment-<workerN|shardM-workerN>.jsonl+
    # (same basename rules as {Coverage::CollectorFragmentMeta}.)
    class RspecFailureFragmentFormatter
      ::RSpec::Core::Formatters.register self, :start, :example_failed

      attr_reader :output

      def initialize(output)
        @output = output
        @path = fragment_path
      end

      def start(_notification)
        FileUtils.mkdir_p(File.dirname(@path))
        File.write(@path, "")
      end

      def example_failed(notification)
        ex = notification.example
        exc = notification.exception
        row = {
          "id" => ex.id,
          "full_description" => ex.full_description,
          "location" => ex.location,
          "file_path" => ex.file_path,
          "line_number" => example_line_number(ex),
          "message" => exc.message.to_s,
          "exception_class" => exc.class.name,
          "polyrun_shard_index" => ENV["POLYRUN_SHARD_INDEX"],
          "polyrun_shard_total" => ENV["POLYRUN_SHARD_TOTAL"],
          "polyrun_shard_matrix_index" => matrix_env_or_nil("POLYRUN_SHARD_MATRIX_INDEX"),
          "polyrun_shard_matrix_total" => matrix_env_or_nil("POLYRUN_SHARD_MATRIX_TOTAL"),
          "rspec_seed" => seed_if_known,
          "rspec_order" => order_if_known
        }
        trim_backtrace!(row, exc)
        File.open(@path, "a") { |f| f.puts(JSON.generate(row.compact)) }
      end

      private

      def example_line_number(ex)
        return ex.line_number if ex.respond_to?(:line_number)

        ex.metadata[:line_number]
      end

      def fragment_path
        dir = ENV.fetch("POLYRUN_FAILURE_FRAGMENT_DIR", FailureMerge::DEFAULT_FRAGMENT_DIR)
        base = Polyrun::Coverage::CollectorFragmentMeta.fragment_default_basename_from_env
        File.expand_path(File.join(dir, "polyrun-failure-fragment-#{base}.jsonl"))
      end

      def matrix_env_or_nil(name)
        v = ENV[name]
        return nil if v.nil? || v.to_s.strip.empty?

        v
      end

      def seed_if_known
        return unless defined?(::RSpec) && ::RSpec.respond_to?(:configuration)

        ::RSpec.configuration.seed
      rescue
        nil
      end

      def order_if_known
        return unless defined?(::RSpec) && ::RSpec.respond_to?(:configuration)

        ::RSpec.configuration.order.to_s
      rescue
        nil
      end

      MAX_BT = 20

      def trim_backtrace!(row, exc)
        bt = exc.backtrace
        return unless bt.is_a?(Array) && bt.any?

        row["backtrace"] = bt.first(MAX_BT)
      end
    end
  end
end
