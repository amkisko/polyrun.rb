module Polyrun
  module Coverage
    module Collector
      module_function

      # Normalizes stdlib Coverage.result to merge-compatible file entries (lines; branches when collected).
      def result_to_blob(raw)
        out = {}
        raw.each do |path, cov|
          next unless cov.is_a?(Hash)

          lines = cov[:lines] || cov["lines"]
          next unless lines.is_a?(Array)

          entry = {"lines" => lines.map { |x| x }}
          br = cov[:branches] || cov["branches"]
          entry["branches"] = br if br
          out[path.to_s] = entry
        end
        out
      end

      def normalize_blob_paths(blob, root)
        root = File.expand_path(root)
        blob.each_with_object({}) do |(path, entry), acc|
          acc[File.expand_path(path.to_s, root)] = entry
        end
      end

      def normalize_groups(groups)
        return nil if groups.nil?

        h = groups.is_a?(Hash) ? groups : {}
        return nil if h.empty?

        h.transform_keys(&:to_s).transform_values(&:to_s)
      end

      def keep_under_root(blob, root, track_under)
        return blob if track_under.nil? || track_under.empty?

        root = File.expand_path(root)
        prefixes = track_under.map { |d| File.join(root, d) }
        blob.each_with_object({}) do |(path, entry), acc|
          p = path.to_s
          next unless prefixes.any? { |pre| p == pre || p.start_with?(pre + "/") }

          acc[path] = entry
        end
      end
    end
  end
end
