require "io/wait"

module Polyrun
  module Quality
    module Command
      DEFAULT_OUTPUT_LIMIT = 1_048_576

      module_function

      # rubocop:disable Metrics/AbcSize -- keep descriptor ownership and process cleanup in the same scope
      def call(argv, root:, timeout:, env: {}, max_output: DEFAULT_OUTPUT_LIMIT)
        timeout = Float(timeout)
        validate!(argv, timeout, max_output)

        started = monotonic
        streams = []
        2.times { streams << IO.pipe }
        output = {"stdout" => +"".b, "stderr" => +"".b}
        pid = Process.spawn(env, [argv.first, argv.first], *argv.drop(1), chdir: root, in: File::NULL, out: streams[0][1], err: streams[1][1], pgroup: true)
        streams.each { |_, writer| writer.close }
        code = collect(pid, streams.map(&:first), output, started + timeout, max_output)
        output.each_value { |value| value.force_encoding(Encoding::UTF_8).scrub!("") }
        output.merge("exitstatus" => code, "wall_s" => monotonic - started)
      rescue Errno::ENOENT => e
        {"stdout" => "", "stderr" => e.message, "exitstatus" => 127, "wall_s" => monotonic - started}
      ensure
        terminate(pid) if pid
        streams&.flatten&.each { |stream| stream.close unless stream.closed? }
      end
      # rubocop:enable Metrics/AbcSize

      def collect(pid, readers, output, deadline, limit)
        active = readers.dup
        status = nil
        loop do
          status ||= Process.waitpid2(pid, Process::WNOHANG)&.last
          return status.exitstatus || 128 + status.termsig if status && active.empty?
          return 124 if monotonic >= deadline

          return 122 if drain(active, readers, output, deadline, limit)
        end
      end

      def drain(active, readers, output, deadline, limit)
        ready = IO.select(active, nil, nil, (deadline - monotonic).clamp(0.0001, 0.001))&.first || []
        ready.each do |reader|
          chunk = reader.read_nonblock(16_384, exception: false)
          if chunk.nil?
            active.delete(reader)
          elsif chunk != :wait_readable
            key = (reader == readers.first) ? "stdout" : "stderr"
            remaining = limit - output.values.sum(&:bytesize)
            output[key] << chunk.byteslice(0, remaining)
            return true if chunk.bytesize > remaining
          end
        end
        false
      end

      def validate!(argv, timeout, max_output)
        raise ArgumentError, "timeout must be finite and positive" unless timeout.finite? && timeout.positive?
        raise ArgumentError, "command must not be empty" unless argv.is_a?(Array) && !argv.empty?
        raise ArgumentError, "output limit must be positive" unless max_output.is_a?(Integer) && max_output.positive?
      end

      def terminate(pid)
        Process.kill("KILL", -pid)
      rescue Errno::ESRCH
        nil
      ensure
        begin
          Process.waitpid(pid)
        rescue Errno::ECHILD
          nil
        end
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
      private_class_method :collect, :drain, :validate!, :terminate, :monotonic
    end
  end
end
