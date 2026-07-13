require_relative "example_diff_track_filter"
require_relative "example_diff_snapshot"

module Polyrun
  module Coverage
    # Per-example line hit deltas from stdlib +Coverage.peek_result+ snapshots.
    module ExampleDiff
      module_function

      # @return [Hash{String=>Hash}] path => sparse line snapshot
      def peek_blob(root: nil, track_under: nil, ignore_paths: nil)
        return {} unless coverage_active?

        snapshot_peek(
          ::Coverage.peek_result,
          root: root,
          track_under: track_under,
          ignore_paths: ignore_paths
        )
      end

      # Frozen snapshot for storage between peeks (stdlib mutates line arrays in place).
      def snapshot_peek(raw, root: nil, track_under: nil, ignore_paths: nil)
        return {} if raw.nil? || raw.empty?

        filter = track_filter_for(root: root, track_under: track_under, ignore_paths: ignore_paths)
        out = {}
        raw.each do |path, coverage_entry|
          next unless coverage_entry.is_a?(Hash)
          next if filter && !filter.include_path?(path.to_s)

          lines = coverage_entry[:lines] || coverage_entry["lines"]
          next unless lines.is_a?(Array)

          out[path.to_s] = Snapshot.sparse_snapshot_lines(lines)
        end
        out
      end

      # +after_source+ may be a normalized blob or a raw +Coverage.peek_result+ hash.
      def diff(before_blob, after_source, root: nil, track_under: nil, ignore_paths: nil)
        filter = track_filter_for(root: root, track_under: track_under, ignore_paths: ignore_paths)
        if raw_peek_result?(after_source)
          diff_against_peek(before_blob, after_source, filter: filter)
        else
          diff_blobs(before_blob, after_source, filter: filter)
        end
      end

      def coverage_active?
        defined?(::Coverage) && ::Coverage.respond_to?(:running?) && ::Coverage.running?
      end

      def diff_blobs(before_blob, after_blob, filter: nil)
        before_blob ||= {}
        after_blob ||= {}
        paths = collect_diff_paths(before_blob, after_blob, filter: filter)
        diff_paths(paths, before_blob, after_blob, raw_after: false)
      end

      def diff_against_peek(before_blob, after_raw, filter: nil)
        before_blob ||= {}
        after_raw ||= {}
        paths = collect_diff_paths(before_blob, after_raw, filter: filter)
        diff_paths(paths, before_blob, after_raw, raw_after: true)
      end

      def filter_lines(lines, root:, track_under:, ignore_paths: [])
        filter = TrackFilter.new(root: root, track_under: track_under, ignore_paths: ignore_paths)
        lines.select { |path, _line, _delta| filter.include_path?(path) }
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

      def line_array(entry)
        return [] unless entry.is_a?(Hash)
        return [] if entry["sparse"]

        arr = entry["lines"] || entry[:lines]
        arr.is_a?(Array) ? arr : []
      end

      def raw_peek_result?(source)
        return false unless source.is_a?(Hash)
        return false if source.empty?

        entry = source.values.first
        entry.is_a?(Hash) && (entry.key?(:lines) || entry.key?(:branches))
      end

      def diff_paths(paths, before_blob, after_blob, raw_after:)
        line_entries = []
        unique = 0
        churn = 0
        max_churn = 0

        paths.each do |path|
          before_entry = before_blob[path]
          after_lines =
            if raw_after
              lines_from_peek_entry(path, after_blob)
            else
              line_array(after_blob[path])
            end

          accumulate_line_delta(before_entry, after_lines) do |delta, line_no|
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

      def collect_diff_paths(before_blob, after_blob, filter: nil)
        keys = before_blob.keys.dup
        after_blob.each_key do |path|
          string_path = path.to_s
          keys << string_path unless keys.include?(string_path)
        end
        return keys unless filter

        keys.select { |path| filter.include_path?(path) }
      end

      def accumulate_line_delta(before_entry, after_lines)
        before_hits = Snapshot.hits_map(before_entry)
        before_max = before_hits.empty? ? 0 : before_hits.keys.max + 1
        max_len = [after_lines.size, before_max].max

        (0...max_len).each do |index|
          before_hit = before_hits[index]
          after_hit = after_lines[index]
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

      def track_filter_for(root:, track_under:, ignore_paths:)
        return nil if track_under.nil? && ignore_paths.nil?

        TrackFilter.new(
          root: root || Dir.pwd,
          track_under: track_under,
          ignore_paths: ignore_paths || []
        )
      end

      def integer_hit(value)
        return 0 if value.nil?
        return 0 if value == "ignored"

        value.is_a?(Integer) ? value : value.to_i
      end
      private_class_method :diff_paths, :collect_diff_paths, :accumulate_line_delta,
        :lines_from_peek_entry, :track_filter_for, :integer_hit, :raw_peek_result?
    end
  end
end
