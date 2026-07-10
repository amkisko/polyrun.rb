module Polyrun
  module RSpec
    module ExampleDebug
      SKIPPED_SQL_PREFIX = /\A(?:SELECT|SET|SHOW|BEGIN|COMMIT|ROLLBACK|RELEASE|SAVEPOINT)/

      module_function

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
      private_class_method :trace_root
    end
  end
end
