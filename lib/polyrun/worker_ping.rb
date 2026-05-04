module Polyrun
  # Writes a monotonic timestamp to +POLYRUN_WORKER_PING_FILE+ when the test process advances
  # (typically once per example). When +location:+ is passed (path:line of the example), the file
  # is two lines: timestamp, then that string. Parents use +--worker-idle-timeout+ to detect a worker with no
  # progress *inside* a single example—unlike a background thread, +ping!+ does not run while Ruby
  # is busy on the main thread, so a tight CPU loop or stuck native code leaves the timestamp stale.
  #
  # Prefer framework installs (call from helpers *after* loading the runner):
  #
  #   require "polyrun/rspec"
  #   Polyrun::RSpec.install_worker_ping!
  #
  #   require "polyrun/minitest"
  #   Polyrun::Minitest.install_worker_ping!
  #
  # Polyrun Quick runs +ping!+ automatically when requiring the Quick stack.
  #
  # Optional interval thread (+POLYRUN_WORKER_PING_THREAD=1+, +POLYRUN_WORKER_PING_INTERVAL_SEC+): call
  # {#ensure_interval_ping_thread!} once at worker startup if you rely on periodic pings without per-example {#ping!};
  # installers call this so the env toggle works out of the box.
  module WorkerPing
    class << self
      def ping!(location: nil)
        path = ping_file_path
        return if path.empty?

        t = Process.clock_gettime(Process::CLOCK_MONOTONIC).to_s
        loc = location.to_s.strip
        payload = loc.empty? ? t : "#{t}\n#{loc}"
        File.binwrite(path, payload)
      rescue SystemCallError
        # best-effort
      end

      def ping_file_path
        ENV["POLYRUN_WORKER_PING_FILE"].to_s.strip
      end

      # Starts a periodic +ping!+ thread when +POLYRUN_WORKER_PING_THREAD+ is truthy and +POLYRUN_WORKER_PING_FILE+ is set.
      # Prefer per-example {#ping!}; safe to call more than once (idempotent).
      # rubocop:disable ThreadSafety/ClassInstanceVariable -- idempotent once-per-process latch
      def ensure_interval_ping_thread!
        thread_flag = ENV["POLYRUN_WORKER_PING_THREAD"]
        return unless %w[1 true yes].include?(thread_flag&.downcase)

        path = ping_file_path
        return if path.empty?

        @interval_ping_mx ||= Mutex.new
        @interval_ping_mx.synchronize do
          return if @interval_ping_started

          raw = ENV["POLYRUN_WORKER_PING_INTERVAL_SEC"].to_s.strip
          interval = Float(raw.empty? ? "15" : raw, exception: false) || 15.0
          interval = 1.0 if interval < 1.0

          ping!
          # rubocop:disable ThreadSafety/NewThread -- optional periodic ping alongside per-example ping!
          Thread.new do
            loop do
              sleep(interval)
              ping!
            rescue SystemCallError, Interrupt
              break
            end
          end
          # rubocop:enable ThreadSafety/NewThread
          @interval_ping_started = true
        end
      end
      # rubocop:enable ThreadSafety/ClassInstanceVariable
    end
  end
end
