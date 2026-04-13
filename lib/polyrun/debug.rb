module Polyrun
  # Opt-in tracing: set +DEBUG=1+ or +POLYRUN_DEBUG=1+ (or +true+).
  # Logs to stderr with wall-clock timestamps; use +.time+ for monotonic durations.
  module Debug
    module_function

    def enabled?
      truthy?(ENV["DEBUG"]) || truthy?(ENV["POLYRUN_DEBUG"])
    end

    def log(message)
      return unless enabled?

      Polyrun::Log.warn "[polyrun debug #{wall_clock}] #{message}"
    end

    def log_kv(pairs)
      return unless enabled?

      log(pairs.map { |k, v| "#{k}=#{v.inspect}" }.join(" "))
    end

    # Same as +log+, but tags lines from parallel RSpec workers so they are not confused with the parent +polyrun+ process (stderr interleaves arbitrarily).
    def log_worker(message)
      return unless enabled?

      if parallel_worker_process?
        Polyrun::Log.warn "[polyrun debug #{wall_clock}] [worker pid=#{$$} shard=#{ENV.fetch("POLYRUN_SHARD_INDEX", "?")}] #{message}"
      else
        Polyrun::Log.warn "[polyrun debug #{wall_clock}] #{message}"
      end
    end

    def log_worker_kv(pairs)
      return unless enabled?

      if parallel_worker_process?
        log_kv({role: "worker", pid: $$, shard: ENV["POLYRUN_SHARD_INDEX"]}.merge(pairs))
      else
        log_kv(pairs)
      end
    end

    def parallel_worker_process?
      ENV["POLYRUN_SHARD_TOTAL"].to_i > 1
    end

    # Yields and logs monotonic duration; re-raises after logging failures.
    def time(label)
      t0 = nil
      return yield unless enabled?

      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      log("#{label} … start")
      result = yield
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
      elapsed_s = format("%0.3f", elapsed)
      log("#{label} … done in #{elapsed_s}s")
      result
    rescue => e
      if t0
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
        elapsed_s = format("%0.3f", elapsed)
        log("#{label} … failed after #{elapsed_s}s: #{e.class}: #{e.message}")
      end
      raise
    end

    def wall_clock
      Time.now.getlocal.strftime("%H:%M:%S.%6N")
    end

    def truthy?(value)
      return false if value.nil?

      v = value.to_s.strip.downcase
      %w[1 true yes on].include?(v)
    end
    private_class_method :truthy?
  end
end
