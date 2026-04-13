module Polyrun
  module Coverage
    # Drop paths from a coverage blob when the path matches any reject pattern (substring).
    # Mirrors SimpleCov +add_filter+ style paths (e.g. "/lib/generators/").
    module Filter
      module_function

      def reject_matching_paths(blob, patterns)
        return blob unless blob.is_a?(Hash)

        pats = Array(patterns).map(&:to_s).reject(&:empty?)
        return blob if pats.empty?

        blob.each_with_object({}) do |(path, entry), acc|
          next if pats.any? { |p| path.to_s.include?(p) }

          acc[path] = entry
        end
      end
    end
  end
end
