module Polyrun
  module Queue
    class FileStore
      private

      def sorted_chunk_files
        Dir.glob(File.join(pending_dir, "[0-9][0-9][0-9][0-9][0-9][0-9].json")).sort
      end

      def take_pending_batch!(meta, batch_size)
        remaining = Integer(meta["pending_count"])
        return [] if remaining <= 0 || batch_size <= 0

        batch = []
        files = sorted_chunk_files
        while batch.size < batch_size
          break if files.empty?

          head = files.first
          append_from_next_chunk!(batch, batch_size, head)
          files.shift unless File.file?(head)
        end

        meta["pending_count"] = [remaining - batch.size, 0].max
        if meta["pending_count"].positive? && sorted_chunk_files.empty?
          raise Polyrun::Error,
            "queue corrupt: pending_count=#{meta["pending_count"]} but no pending chunk files under #{pending_dir}"
        end

        batch
      end

      def append_from_next_chunk!(batch, batch_size, path)
        chunk = JSON.parse(File.read(path))
        raise Polyrun::Error, "corrupt queue chunk: #{path}" unless chunk.is_a?(Array)

        need = batch_size - batch.size
        taken = chunk.shift(need)
        batch.concat(taken)
        if chunk.empty?
          FileUtils.rm_f(path)
        else
          atomic_write(path, JSON.generate(chunk))
        end
      end
    end
  end
end
