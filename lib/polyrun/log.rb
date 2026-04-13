# rubocop:disable ThreadSafety/ClassAndModuleAttributes, ThreadSafety/ClassInstanceVariable -- process-global IO routing for CLI
module Polyrun
  # Swappable sinks for CLI and library output. Defaults match +Kernel#warn+ (stderr) and +puts+/+print+ (stdout).
  #
  # Assign an IO, +StringIO+, Ruby +Logger+, or any object responding to +puts+, +write+, or +warn+ (Logger).
  #
  #   Polyrun::Log.stderr = Logger.new($stderr)
  #   Polyrun::Log.stdout = StringIO.new
  module Log
    class << self
      attr_writer :stderr
      attr_writer :stdout

      def stderr
        @stderr || $stderr
      end

      def stdout
        @stdout || $stdout
      end

      def warn(msg = nil)
        return if msg.nil?

        emit_line(stderr, msg)
      end

      def puts(msg = "")
        if msg.nil?
          stdout.write("\n")
        else
          emit_line(stdout, msg)
        end
      end

      def print(msg = "")
        io = stdout
        if io.respond_to?(:write)
          io.write(msg.to_s)
        elsif io.respond_to?(:print)
          io.print(msg.to_s)
        end
      end

      # Clears custom sinks so +stderr+ / +stdout+ resolve to the current global +$stderr+ / +$stdout+ (e.g. after tests).
      def reset_io!
        @stderr = nil
        @stdout = nil
      end

      private

      def emit_line(io, msg)
        s = msg.to_s
        if logger_like?(io)
          io.warn(s.chomp)
        elsif io.respond_to?(:puts)
          io.puts(s)
        else
          io.write(s.end_with?("\n") ? s : "#{s}\n")
        end
      end

      def logger_like?(io)
        io.respond_to?(:warn) && !io.is_a?(IO)
      end
    end
  end
end
# rubocop:enable ThreadSafety/ClassAndModuleAttributes, ThreadSafety/ClassInstanceVariable
