require "timeout"

module Polyrun
  module RSpec
    # Per-example RSpec debugging for local investigation (SQL, TracePoint, timeouts).
    #
    # +POLYRUN_EXAMPLE_DEBUG=1+ enables installers; +DEBUG=1+ / +POLYRUN_DEBUG=1+ trace orchestration only.
    # +POLYRUN_DEBUG_SQL=1+ or legacy +DEBUG_SQL=1+ logs mutating SQL.
    # +POLYRUN_DEBUG_TRACE=1+ or legacy +DEBUG_TRACE=1+ traces :call/:raise under the app root.
    module ExampleDebug
      SKIPPED_SQL_PREFIX = /\A(?:SELECT|SET|SHOW|BEGIN|COMMIT|ROLLBACK|RELEASE|SAVEPOINT)/

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
        Integer(ENV.fetch("DEBUG_LOG_LEVEL", "0"))
      rescue ArgumentError
        0
      end

      def rails_log_level
        case log_level
        when 0 then :debug
        when 1 then :info
        when 2 then :warn
        when 3 then :error
        else :fatal
        end
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

          level = log_level
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
          @spec_file_path = group[:file_path]
          @spec_line_number = group[:line_number]

          def spec_dirname
            File.dirname(@spec_file_path)
          end

          def spec_basename
            File.basename(@spec_file_path)
          end

          if Polyrun::RSpec::ExampleDebug.print_spec_enabled?
            Polyrun::Log.puts "\nRunning #{@spec_file_path}:#{@spec_line_number}\n"
          end
        end

        rspec_config.after do
          if Polyrun::RSpec::ExampleDebug.print_spec_enabled?
            Polyrun::Log.puts "\nFinished #{@spec_file_path}:#{@spec_line_number}\n"
          end
        end
      end

      def install_sql_debug!(rspec_config, io: Polyrun::Log.stdout)
        return unless defined?(ActiveSupport::Notifications)

        rspec_config.around do |example|
          subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |event|
            payload = event.payload[:sql]
            next unless loggable_sql?(payload)

            line = sql_with_interpolated_binds(payload, event.payload[:type_casted_binds])
            io.puts "+ #{line}"
          end

          example.run
        ensure
          ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
        end
      end

      def install_trace_debug!(rspec_config, root: trace_root, io: Polyrun::Log.stdout)
        require "pp"
        root_path = File.expand_path(root.to_s)
        trace = TracePoint.new do |trace_point|
          if trace_point.event == :call && trace_point.path.to_s.start_with?(root_path)
            io.puts PP.pp({event: :call, path: "#{trace_point.path}:#{trace_point.lineno}"}, +"")
          elsif trace_point.event == :raise
            io.puts PP.pp(
              {
                event: :raise,
                raised_exception: trace_point.raised_exception,
                path: "#{trace_point.path}:#{trace_point.lineno}",
                method_id: trace_point.method_id
              },
              +""
            )
          end
        end

        rspec_config.around do |example|
          trace.enable
          example.run
        ensure
          trace.disable
        end
      end

      def loggable_sql?(sql)
        !sql.to_s.match?(SKIPPED_SQL_PREFIX)
      end

      def sql_with_interpolated_binds(sql, binds)
        output = sql.to_s.dup
        Array(binds).each_with_index do |bind, index|
          output = output.gsub("$#{index + 1}", "'#{bind}'")
        end
        output
      end

      def trace_root
        return Rails.root.to_s if defined?(Rails)

        Dir.pwd
      end

      def fetch_rspec_configuration!
        require "rspec/core"
        ::RSpec.configuration
      end

      def truthy?(value)
        return false if value.nil?

        %w[1 true yes on].include?(value.to_s.strip.downcase)
      end
      private_class_method :truthy?, :trace_root, :fetch_rspec_configuration!
    end
  end
end
