require "fileutils"
require "time"

module Polyrun
  # Routes parallel worker stdout/stderr through per-shard log files with optional prefixed TTY echo.
  #
  # Opt-in: +POLYRUN_WORKER_OUTPUT_ROUTING=1+ (or set +POLYRUN_WORKER_LOG_DIR+).
  # +POLYRUN_WORKER_OUTPUT_ROUTING=0+ keeps inherited stdio (default polyrun behavior).
  # +POLYRUN_WORKER_OUTPUT_PREFIX=0+ writes logs only (no live prefixed echo).
  module WorkerOutput
    class LineForwarder
      def initialize(shard:, pid:, log_io:, prefix_live:, tty_io:)
        @shard = shard
        @pid = pid
        @log_io = log_io
        @prefix_live = prefix_live
        @tty_io = tty_io
        @buffer = +""
        @mutex = Mutex.new
      end

      def consume(chunk)
        return if chunk.nil? || chunk.empty?

        @mutex.synchronize do
          if progress_chunk?(chunk)
            write_tty(chunk)
            @log_io&.write(chunk)
            return
          end

          @buffer << chunk
          while (newline_index = @buffer.index("\n"))
            emit_line(@buffer.slice!(0, newline_index + 1))
          end
        end
      end

      def flush
        @mutex.synchronize do
          next if @buffer.empty?

          emit_line(@buffer)
          @buffer.clear
        end
      end

      private

      def progress_chunk?(chunk)
        chunk.include?("\r") && !chunk.include?("\n")
      end

      def emit_line(line)
        prefixed = "#{prefix}#{line}"
        @log_io&.write(prefixed)
        write_tty(prefixed) if @prefix_live
      end

      def prefix
        "[#{Time.now.strftime("%Y-%m-%dT%H:%M:%S")} shard=#{@shard} pid=#{@pid}] "
      end

      def write_tty(text)
        @tty_io.write(text)
        @tty_io.flush
      end
    end

    class WorkerForwarder
      def initialize(shard:, pid:, log_path:, prefix_live:)
        @shard = shard
        @pid = pid
        @log_io = File.open(log_path, "wb")
        @stdout = LineForwarder.new(shard: shard, pid: pid, log_io: @log_io, prefix_live: prefix_live, tty_io: Polyrun::Log.stdout)
        @stderr = LineForwarder.new(shard: shard, pid: pid, log_io: @log_io, prefix_live: prefix_live, tty_io: Polyrun::Log.stderr)
        @write_mutex = Mutex.new
      end

      def consume(stream, chunk)
        @write_mutex.synchronize do
          case stream
          when :stdout then @stdout.consume(chunk)
          when :stderr then @stderr.consume(chunk)
          end
        end
      end

      def close
        @stdout.flush
        @stderr.flush
        @log_io.close
      end
    end

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

    def registry
      @registry ||= {}
    end
    private_class_method :registry

    def forwarder_thread(io, forwarder, stream)
      Thread.new do
        loop do
          forwarder.consume(stream, io.readpartial(4096))
        end
      rescue EOFError, IOError, Errno::EPIPE
        # worker closed the pipe
      ensure
        io.close unless io.closed?
      end
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
