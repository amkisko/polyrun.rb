require "time"

module Polyrun
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
  end
end
