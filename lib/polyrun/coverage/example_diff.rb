module Polyrun
  module Coverage
    # Per-example line hit deltas from stdlib +Coverage.peek_result+ snapshots.
    module ExampleDiff
      module_function

      # @return [Hash{String=>Hash}] path => +{"lines"=>[...]}+
      def peek_blob
        return {} unless coverage_active?

        snapshot_peek(::Coverage.peek_result)
      end

      # Frozen snapshot for storage between peeks (dup line arrays; stdlib mutates in place).
      def snapshot_peek(raw)
        return {} if raw.nil? || raw.empty?

        normalize_peek(raw)
      end

      def normalize_peek(raw)
        out = {}
        raw.each do |path, cov|
          next unless cov.is_a?(Hash)

          lines = cov[:lines] || cov["lines"]
          next unless lines.is_a?(Array)

          out[path.to_s] = {"lines" => lines.dup}
        end
        out
      end

      # +after_source+ may be a normalized blob or a raw +Coverage.peek_result+ hash.
      # @return [Hash] +:unique_lines+, +:line_churn+, +:max_line_churn+, +:lines+ (compact triples)
      def diff(before_blob, after_source)
        if raw_peek_result?(after_source)
          diff_against_peek(before_blob, after_source)
        else
          diff_blobs(before_blob, after_source)
        end
      end

      def coverage_active?
        defined?(::Coverage) && ::Coverage.respond_to?(:running?) && ::Coverage.running?
      end

      def raw_peek_result?(source)
        return false unless source.is_a?(Hash)
        return false if source.empty?

        entry = source.values.first
        entry.is_a?(Hash) && (entry.key?(:lines) || entry.key?(:branches))
      end

      # rubocop:disable Metrics/AbcSize -- per-file coverage delta walk
      def diff_blobs(before_blob, after_blob)
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
          accumulate_line_delta(path, b_lines, a_lines) do |delta, line_no|
            unique += 1
            churn += delta
            max_churn = delta if delta > max_churn
            line_entries << [path, line_no, delta]
          end
        end

        {
          unique_lines: unique,
          line_churn: churn,
          max_line_churn: max_churn,
          lines: line_entries
        }
      end

      def diff_against_peek(before_blob, after_raw)
        before_blob ||= {}
        after_raw ||= {}
        files = before_blob.keys | after_raw.keys.map(&:to_s)

        line_entries = []
        unique = 0
        churn = 0
        max_churn = 0

        files.each do |path|
          b_lines = line_array(before_blob[path])
          a_lines = lines_from_peek_entry(path, after_raw)
          accumulate_line_delta(path, b_lines, a_lines) do |delta, line_no|
            unique += 1
            churn += delta
            max_churn = delta if delta > max_churn
            line_entries << [path, line_no, delta]
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

      def accumulate_line_delta(path, b_lines, a_lines)
        max_len = [b_lines.size, a_lines.size].max

        (0...max_len).each do |index|
          before_hit = b_lines[index]
          after_hit = a_lines[index]
          next if after_hit.nil? && before_hit.nil?

          delta = integer_hit(after_hit) - integer_hit(before_hit)
          next unless delta.positive?

          yield(delta, index + 1)
        end
      end

      def lines_from_peek_entry(path, after_raw)
        entry = after_raw[path] || after_raw[path.to_s]
        return [] unless entry.is_a?(Hash)

        arr = entry[:lines] || entry["lines"]
        arr.is_a?(Array) ? arr : []
      end

      def filter_lines(lines, root:, track_under:, ignore_paths: [])
        root = File.expand_path(root)
        prefixes = Array(track_under).map { |directory| File.join(root, directory.to_s) }
        ignore = Array(ignore_paths).map(&:to_s).reject(&:empty?)

        lines.select do |path, _line, _delta|
          absolute = File.expand_path(path.to_s, root)
          next false if ignore.any? { |pattern| path_matches_ignore?(absolute, pattern) }

          prefixes.any? { |prefix| absolute == prefix || absolute.start_with?(prefix + "/") }
        end
      end

      def apply_track_under(delta, root:, track_under:, ignore_paths: [])
        filtered = filter_lines(delta[:lines] || [], root: root, track_under: track_under, ignore_paths: ignore_paths)
        unique = filtered.size
        churn = filtered.sum { |(_path, _line, hit_delta)| hit_delta }
        max_churn = filtered.map { |(_path, _line, hit_delta)| hit_delta }.max || 0
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
      private_class_method :accumulate_line_delta, :line_array, :integer_hit, :lines_from_peek_entry, :raw_peek_result?
    end
  end
end
