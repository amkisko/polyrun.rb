module Polyrun
  module Database
    # ENV helpers for sharded test databases (parallel_tests–style), stdlib only.
    module Shard
      module_function

      # Builds a hash of suggested ENV vars for this shard (strings).
      def env_map(shard_index:, shard_total:, base_database: nil)
        idx = Integer(shard_index)
        tot = Integer(shard_total)
        raise Polyrun::Error, "shard_index out of range" if idx < 0 || idx >= tot

        out = {
          "POLYRUN_SHARD_INDEX" => idx.to_s,
          "POLYRUN_SHARD_TOTAL" => tot.to_s
        }
        out["TEST_ENV_NUMBER"] = (idx + 1).to_s if tot > 1
        if base_database && !base_database.to_s.empty?
          out["POLYRUN_TEST_DATABASE"] = expand_database_name(base_database.to_s, idx)
        end
        out
      end

      def expand_database_name(template, shard_index)
        template.gsub("%{shard}", Integer(shard_index).to_s).gsub("%<shard>d", format("%d", Integer(shard_index)))
      end

      # Common URL transform: shard suffix on the database segment (+scheme://host/...+) or +sqlite3:+ path.
      def database_url_with_shard(url, shard_index)
        return url if url.nil? || url.to_s.empty?

        u = url.to_s
        return u if u.start_with?("http://", "https://", "file://")

        if u.match?(/\Asqlite3:/i)
          path = u.sub(/\Asqlite3:/i, "")
          if path.match?(%r{([^/]+?)(\.sqlite3)\z}i)
            idx = Integer(shard_index)
            new_path = path.sub(%r{([^/]+?)(\.sqlite3)\z}i) { "#{$1}_#{idx}#{$2}" }
            return "sqlite3:#{new_path}"
          end
          return u
        end

        return u unless u.match?(%r{\A[a-z][a-z0-9+.-]*://}i)

        if (m = u.match(%r{/([^/?]+)(\?|$)}))
          base = m[1]
          suffixed = "#{base}_#{Integer(shard_index)}"
          u.sub(%r{/#{Regexp.escape(base)}(\?|$)}, "/#{suffixed}\\1")
        else
          u
        end
      end

      def print_exports(shard_index:, shard_total:, base_database: nil)
        env_map(shard_index: shard_index, shard_total: shard_total, base_database: base_database).each do |k, v|
          Polyrun::Log.puts %(export #{k}=#{v})
        end
      end
    end
  end
end
