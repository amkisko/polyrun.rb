module Polyrun
  module Coverage
    # Per-example line hit deltas from stdlib +Coverage.peek_result+ snapshots.
    module ExampleDiff
      module_function

      # @return [Hash{String=>Hash}] path => +{"lines"=>[...]}+
      def peek_blob
        return {} unless coverage_active?

        normalize_peek(::Coverage.peek_result)
      end

      def coverage_active?
        defined?(::Coverage) && ::Coverage.respond_to?(:running?) && ::Coverage.running?
      end

      def normalize_peek(raw)
        out = {}
        raw.each do |path, cov|
          next unless cov.is_a?(Hash)

          lines = cov[:lines] || cov["lines"]
          next unless lines.is_a?(Array)

          out[path.to_s] = {"lines" => lines.map { |x| x }}
        end
        out
      end

      # @return [Hash] +:unique_lines+, +:line_churn+, +:max_line_churn+, +:lines+ (compact triples)
      # rubocop:disable Metrics/AbcSize -- per-file coverage delta walk
      def diff(before_blob, after_blob)
        before_blob ||= {}
        after_blob ||= {}
        files = before_blob.keys | after_blob.keys

        line_entries = []
        unique = 0
        churn = 0
        max_churn = 0

        files.each do |path|
          b_lines = line_array(before_blob[path])
          a_lines = line_array(after_blob[path])
          max_len = [b_lines.size, a_lines.size].max

          (0...max_len).each do |i|
            b = b_lines[i]
            a = a_lines[i]
            next if a.nil? && b.nil?

            delta = (integer_hit(a) - integer_hit(b))
            next unless delta.positive?

            line_no = i + 1
            line_entries << [path, line_no, delta]
            unique += 1
            churn += delta
            max_churn = delta if delta > max_churn
          end
        end

        {
          unique_lines: unique,
          line_churn: churn,
          max_line_churn: max_churn,
          lines: line_entries
        }
      end
      # rubocop:enable Metrics/AbcSize

      def filter_lines(lines, root:, track_under:, ignore_paths: [])
        root = File.expand_path(root)
        prefixes = Array(track_under).map { |d| File.join(root, d.to_s) }
        ignore = Array(ignore_paths).map(&:to_s).reject(&:empty?)

        lines.select do |path, _line, _delta|
          p = File.expand_path(path.to_s, root)
          next false if ignore.any? { |pat| path_matches_ignore?(p, pat) }

          prefixes.any? { |pre| p == pre || p.start_with?(pre + "/") }
        end
      end

      def apply_track_under(delta, root:, track_under:, ignore_paths: [])
        filtered = filter_lines(delta[:lines] || [], root: root, track_under: track_under, ignore_paths: ignore_paths)
        unique = filtered.size
        churn = filtered.sum { |(_p, _l, d)| d }
        max_churn = filtered.map { |(_p, _l, d)| d }.max || 0
        {
          unique_lines: unique,
          line_churn: churn,
          max_line_churn: max_churn,
          lines: filtered
        }
      end

      def path_matches_ignore?(path, pattern)
        return path.include?(pattern) if pattern.is_a?(String) && !pattern.start_with?("/")

        path.match?(Regexp.new(pattern))
      rescue RegexpError
        path.include?(pattern.to_s)
      end

      def line_array(entry)
        return [] unless entry.is_a?(Hash)

        arr = entry["lines"] || entry[:lines]
        arr.is_a?(Array) ? arr : []
      end

      def integer_hit(value)
        return 0 if value.nil?

        value.is_a?(Integer) ? value : value.to_i
      end
      private_class_method :line_array, :integer_hit
    end
  end
end
