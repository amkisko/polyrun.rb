module Polyrun
  module Coverage
    # Shard / worker naming for coverage JSON fragments (N×M CI vs run-shards).
    module CollectorFragmentMeta
      module_function

      # Default fragment basename (no extension) for +coverage/polyrun-fragment-<basename>.json+.
      def fragment_default_basename_from_env(env = ENV)
        local = env.fetch("POLYRUN_SHARD_INDEX", "0")
        mt = env["POLYRUN_SHARD_MATRIX_TOTAL"].to_i
        if mt > 1
          mi = env.fetch("POLYRUN_SHARD_MATRIX_INDEX", "0")
          "shard#{mi}-worker#{local}"
        elsif env["POLYRUN_SHARD_TOTAL"].to_i > 1
          "worker#{local}"
        else
          local
        end
      end

      def finish_debug_time_label
        mt = ENV["POLYRUN_SHARD_MATRIX_TOTAL"].to_i
        if mt > 1
          "worker pid=#{$$} shard(matrix)=#{ENV.fetch("POLYRUN_SHARD_MATRIX_INDEX", "?")} worker(local)=#{ENV.fetch("POLYRUN_SHARD_INDEX", "?")} Coverage::Collector.finish (write fragment)"
        elsif ENV["POLYRUN_SHARD_TOTAL"].to_i > 1
          "worker pid=#{$$} worker=#{ENV.fetch("POLYRUN_SHARD_INDEX", "?")} Coverage::Collector.finish (write fragment)"
        else
          "Coverage::Collector.finish (write fragment)"
        end
      end

      def fragment_meta_from_env(basename)
        mt = ENV["POLYRUN_SHARD_MATRIX_TOTAL"].to_i
        {
          basename: basename,
          worker_index: ENV.fetch("POLYRUN_SHARD_INDEX", "0"),
          shard_matrix_index: shard_matrix_index_value(mt)
        }
      end

      def shard_matrix_index_value(matrix_total)
        return nil if matrix_total <= 1

        ENV.fetch("POLYRUN_SHARD_MATRIX_INDEX", "0")
      end

      def merge_fragment_meta!(m, fm)
        return m if fm.nil?

        m["polyrun_fragment_basename"] = fm[:basename].to_s if fm[:basename]
        m["polyrun_worker_index"] = fm[:worker_index].to_s if fm[:worker_index]
        m["polyrun_shard_matrix_index"] = fm[:shard_matrix_index].to_s if fm[:shard_matrix_index]
        m
      end
    end
  end
end
