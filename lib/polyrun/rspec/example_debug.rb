require "logger"
require "timeout"
require_relative "example_debug_instrumentation"

module Polyrun
  module RSpec
    # Per-example RSpec debugging for local investigation (SQL, TracePoint, timeouts).
    #
    # +POLYRUN_EXAMPLE_DEBUG=1+ enables installers; +DEBUG=1+ / +POLYRUN_DEBUG=1+ trace orchestration only.
    # +POLYRUN_DEBUG_SQL=1+ or legacy +DEBUG_SQL=1+ logs mutating SQL.
    # +POLYRUN_DEBUG_TRACE=1+ or legacy +DEBUG_TRACE=1+ traces :call/:raise under the app root.
    # +DEBUG_LOG_LEVEL+ accepts Ruby Logger severities as integers (0 debug … 4 fatal) or names.
    module ExampleDebug
      LOG_LEVEL_BY_NAME = {
        "debug" => Logger::DEBUG,
        "info" => Logger::INFO,
        "warn" => Logger::WARN,
        "error" => Logger::ERROR,
        "fatal" => Logger::FATAL
      }.freeze

      module_function

      def enabled?
        truthy?(ENV["POLYRUN_EXAMPLE_DEBUG"])
      end

      def sql_enabled?
        enabled? && (truthy?(ENV["POLYRUN_DEBUG_SQL"]) || truthy?(ENV["DEBUG_SQL"]))
      end

      def trace_enabled?
        enabled? && (truthy?(ENV["POLYRUN_DEBUG_TRACE"]) || truthy?(ENV["DEBUG_TRACE"]))
      end

      def prosopite_enabled?
        enabled? && truthy?(ENV["DEBUG_PROSOPITE"])
      end

      def print_spec_enabled?
        enabled? && truthy?(ENV["DEBUG_PRINT_SPEC"])
      end

      def example_timeout_disabled?
        enabled?
      end

      def log_level
        parse_log_level(ENV.fetch("DEBUG_LOG_LEVEL", "debug"))
      end

      def rails_log_level
        case log_level
        when Logger::DEBUG then :debug
        when Logger::INFO then :info
        when Logger::WARN then :warn
        when Logger::ERROR then :error
        else :fatal
        end
      end

      def parse_log_level(raw)
        normalized = raw.to_s.strip.downcase
        return LOG_LEVEL_BY_NAME.fetch(normalized) if LOG_LEVEL_BY_NAME.key?(normalized)

        Integer(normalized)
      rescue ArgumentError
        Logger::DEBUG
      end

      def install!(rspec_config: fetch_rspec_configuration!)
        install_spec_path_helpers!(rspec_config)
        install_sql_debug!(rspec_config) if sql_enabled?
        install_trace_debug!(rspec_config) if trace_enabled?
      end

      def install_rails_logging!(rspec_config: fetch_rspec_configuration!)
        return unless enabled?
        return unless defined?(Rails)

        rspec_config.before do |example|
          group = example.metadata[:example_group]
          Polyrun::Log.puts "\n\nRunning #{group[:file_path]}:#{group[:line_number]}"

          level = ExampleDebug.log_level
          Rails.logger.level = level
          if defined?(ActiveRecord::Base)
            ar_logger = Logger.new(Polyrun::Log.stdout)
            ar_logger.level = level
            ActiveRecord::Base.logger = ar_logger
          end
        end
      end

      def install_example_timeout!(
        rspec_config,
        seconds: ENV.fetch("RSPEC_EXAMPLE_TIMEOUT_SEC", "30").to_f
      )
        return if seconds <= 0
        return if example_timeout_disabled?

        rspec_config.around(:each) do |example|
          if example.metadata[:benchmark] || example.metadata[:slow]
            example.run
          else
            Timeout.timeout(seconds) { example.run }
          end
        rescue Timeout::Error
          raise "Example timed out after #{seconds}s (#{example.location})"
        end
      end

      def install_prosopite!(rspec_config: fetch_rspec_configuration!)
        return unless prosopite_enabled?
        return unless defined?(Prosopite) && defined?(Rails)

        log_path = Rails.root.join("tmp", "prosopite_#{Time.current.strftime("%Y%m%d_%H%M%S")}.log")
        Prosopite.custom_logger = Logger.new(log_path)

        rspec_config.before { Prosopite.scan }
        rspec_config.after { Prosopite.finish }
      end

      def install_spec_path_helpers!(rspec_config)
        rspec_config.before do |example|
          group = example.metadata[:example_group]
          spec_file_path = group[:file_path]

          define_singleton_method(:spec_dirname) { File.dirname(spec_file_path) }
          define_singleton_method(:spec_basename) { File.basename(spec_file_path) }

          if ExampleDebug.print_spec_enabled?
            Polyrun::Log.puts "\nRunning #{spec_file_path}:#{group[:line_number]}\n"
          end
        end

        rspec_config.after do |example|
          next unless ExampleDebug.print_spec_enabled?

          group = example.metadata[:example_group]
          Polyrun::Log.puts "\nFinished #{group[:file_path]}:#{group[:line_number]}\n"
        end
      end

      def fetch_rspec_configuration!
        require "rspec/core"
        ::RSpec.configuration
      end

      def truthy?(value)
        return false if value.nil?

        %w[1 true yes on].include?(value.to_s.strip.downcase)
      end
      private_class_method :truthy?, :parse_log_level, :fetch_rspec_configuration!
    end
  end
end
