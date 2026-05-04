# rubocop:disable ThreadSafety/ClassAndModuleAttributes, ThreadSafety/ClassInstanceVariable -- process-global IO routing for CLI
module Polyrun
  # Swappable sinks for CLI and library output. Defaults match +Kernel#warn+ (stderr) and +puts+/+print+ (stdout).
  #
  # Assign an IO, +StringIO+, Ruby +Logger+, or any object responding to +puts+, +write+, or +warn+ (Logger).
  #
  #   Polyrun::Log.stderr = Logger.new($stderr)
  #   Polyrun::Log.stdout = StringIO.new
  #
  # Orchestration (+orchestration_warn+): worker timeout and SIGINT lines use the same sink as +warn+ unless
  # +POLYRUN_ORCHESTRATION_STDERR=1+ and stderr is not process +$stderr+ (then the summary is copied to +$stderr+).
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

      # Like {#warn}, and when +POLYRUN_ORCHESTRATION_STDERR=1+ and {#stderr} is not the process +$stderr+,
      # also writes one line to +$stderr+ so timeout/interrupt attribution survives custom/null Log sinks.
      def orchestration_warn(msg)
        warn(msg)
        return unless %w[1 true yes].include?(ENV["POLYRUN_ORCHESTRATION_STDERR"]&.downcase)
        return if stderr.equal?($stderr)

        # Intentionally the real stderr stream (+Kernel#warn+ routes through +Log.stderr+).
        # rubocop:disable Style/StderrPuts
        $stderr.puts(msg.to_s.chomp)
        # rubocop:enable Style/StderrPuts
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
