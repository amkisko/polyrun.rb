require "fileutils"
require_relative "worker_output_forwarders"

module Polyrun
  # Routes parallel worker stdout/stderr through per-shard log files with optional prefixed TTY echo.
  #
  # Opt-in: +POLYRUN_WORKER_OUTPUT_ROUTING=1+ (or set +POLYRUN_WORKER_LOG_DIR+).
  # +POLYRUN_WORKER_OUTPUT_ROUTING=0+ keeps inherited stdio (default polyrun behavior).
  # +POLYRUN_WORKER_OUTPUT_PREFIX=0+ writes logs only (no live prefixed echo).
  module WorkerOutput
    module_function

    def routing_enabled?
      return false if disabled_by_env?

      truthy?(ENV["POLYRUN_WORKER_OUTPUT_ROUTING"]) || !log_directory.nil?
    end

    def log_directory
      value = ENV["POLYRUN_WORKER_LOG_DIR"]
      return nil if value.nil?

      stripped = value.to_s.strip
      stripped.empty? ? nil : stripped
    end

    def prefix_live?
      return true if ENV["POLYRUN_WORKER_OUTPUT_PREFIX"].nil?

      truthy?(ENV["POLYRUN_WORKER_OUTPUT_PREFIX"])
    end

    def log_path_for(shard)
      File.expand_path("shard-#{shard}.log", log_directory || default_log_directory)
    end

    def worker_log_directory_label
      log_directory || default_log_directory
    end

    def prepare_log_dir!
      directory = log_directory || default_log_directory
      FileUtils.mkdir_p(directory)
      Dir.glob(File.join(directory, "shard-*.log")).each { |path| File.delete(path) }
    end

    def warn_shard_log(shard)
      return unless routing_enabled?

      Polyrun::Log.warn "polyrun run-shards: shard #{shard} worker log → #{log_path_for(shard)}"
    end

    def spawn_worker(child_env, cmd, paths, hook_cfg)
      shard = child_env.fetch("POLYRUN_SHARD_INDEX", "?")
      out_read, out_write = IO.pipe
      err_read, err_write = IO.pipe

      pid =
        if hook_cfg.worker_hooks? && !Polyrun::Hooks.disabled?
          Process.spawn(
            child_env,
            "sh",
            "-c",
            hook_cfg.build_worker_shell_script(cmd, paths),
            out: out_write,
            err: err_write
          )
        else
          Process.spawn(child_env, *cmd, *paths, out: out_write, err: err_write)
        end

      out_write.close
      err_write.close

      start_forwarders(
        pid: pid,
        shard: shard,
        stdout_io: out_read,
        stderr_io: err_read,
        log_path: log_path_for(shard)
      )
      pid
    end

    def start_forwarders(pid:, shard:, stdout_io:, stderr_io:, log_path:)
      forwarder = WorkerForwarder.new(
        shard: shard,
        pid: pid,
        log_path: log_path,
        prefix_live: prefix_live?
      )
      threads = [
        forwarder_thread(stdout_io, forwarder, :stdout),
        forwarder_thread(stderr_io, forwarder, :stderr)
      ]
      registry[pid] = {threads: threads, ios: [stdout_io, stderr_io], forwarder: forwarder}
    end

    def finish_worker(pid)
      entry = registry.delete(pid)
      return unless entry

      drain_forwarders(entry)
    end

    def shutdown_all!
      registry.each_value { |entry| drain_forwarders(entry) }
      registry.clear
    end

    def default_log_directory
      "tmp/polyrun/workers"
    end

    def disabled_by_env?
      %w[0 false no off].include?(ENV["POLYRUN_WORKER_OUTPUT_ROUTING"].to_s.strip.downcase)
    end

    def truthy?(value)
      return false if value.nil?

      %w[1 true yes on].include?(value.to_s.strip.downcase)
    end
    private_class_method :truthy?

    # rubocop:disable ThreadSafety/ClassInstanceVariable -- per-parent-process worker forwarder registry
    def registry
      @registry ||= {}
    end
    private_class_method :registry
    # rubocop:enable ThreadSafety/ClassInstanceVariable

    def forwarder_thread(io, forwarder, stream)
      # rubocop:disable ThreadSafety/NewThread -- one reader thread per worker pipe
      Thread.new do
        loop do
          forwarder.consume(stream, io.readpartial(4096))
        end
      rescue IOError, Errno::EPIPE, EOFError
        begin
          remaining = io.read
          forwarder.consume(stream, remaining) if remaining && !remaining.empty?
        rescue IOError, EOFError, Errno::EPIPE
          nil
        end
      ensure
        io.close unless io.closed?
      end
      # rubocop:enable ThreadSafety/NewThread
    end
    private_class_method :forwarder_thread

    def drain_forwarders(entry)
      entry[:ios].each do |io|
        io.close unless io.closed?
      rescue IOError
        nil
      end
      entry[:threads].each(&:join)
      entry[:forwarder].close
    end
    private_class_method :drain_forwarders
  end
end
