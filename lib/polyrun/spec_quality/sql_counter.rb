module Polyrun
  module SpecQuality
    # Optional per-example SQL query counting via ActiveSupport::Notifications.
    module SqlCounter
      class << self
        def install!
          return false unless notifications_available?
          return true if @installed

          @installed = true
          @subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
            next unless Polyrun::SpecQuality.recording?

            event = ActiveSupport::Notifications::Event.new(*args)
            Polyrun::SpecQuality.record_sql!(event.payload[:sql].to_s)
          end
          true
        end

        def uninstall!
          return unless @installed && @subscriber

          ActiveSupport::Notifications.unsubscribe(@subscriber)
          @subscriber = nil
          @installed = false
        end

        def notifications_available?
          defined?(ActiveSupport::Notifications)
        end
      end
    end
  end
end
