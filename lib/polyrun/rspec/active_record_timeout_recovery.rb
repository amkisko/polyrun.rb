module Polyrun
  module RSpec
    # Drops pooled connections after per-example Timeout interrupts database I/O.
    # Uses only ActiveRecord connection-pool APIs (PostgreSQL, MySQL, SQLite, SQL Server, etc.).
    module ActiveRecordTimeoutRecovery
      module_function

      def disconnect_all_connection_pools!
        return unless active_record_loaded?

        if defined?(ActiveRecord) && ActiveRecord.respond_to?(:disconnect_all!)
          ActiveRecord.disconnect_all!
          return
        end

        each_connection_pool(&:disconnect!)
      end

      def active_record_loaded?
        defined?(ActiveRecord::Base) &&
          ActiveRecord::Base.respond_to?(:connection_handler)
      end

      def each_connection_pool
        connection_handlers.each do |handler|
          pools_for(handler).each { |pool| yield pool }
        end
      end

      def connection_handlers
        base = ActiveRecord::Base
        if base.respond_to?(:connection_handlers)
          base.connection_handlers.values
        else
          [base.connection_handler]
        end
      end

      def pools_for(handler)
        if handler.respond_to?(:all_connection_pools)
          handler.all_connection_pools
        elsif handler.respond_to?(:connection_pool_list)
          handler.connection_pool_list
        else
          []
        end
      end
      private_class_method :active_record_loaded?, :each_connection_pool, :connection_handlers, :pools_for
    end
  end
end
