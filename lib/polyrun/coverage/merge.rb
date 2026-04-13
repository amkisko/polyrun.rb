require "json"

module Polyrun
  module Coverage
    # Merges SimpleCov-compatible coverage blobs (line arrays and optional branches).
    # Intended to be replaced or accelerated by a native extension for large suites.
    #
    # Complexity: +merge_two+ is linear in the number of file keys in its operands. Shards are combined with
    # +merge_blob_tree+ (pairwise rounds), so total work stays linear in the sum of blob sizes across shards
    # (same asymptotic cost as a left fold; shallower call depth). Group recomputation after merge is
    # O(files x groups) with one pass over files (+TrackFiles.group_summaries+).
    module Merge
      module_function

      # Merged coverage blob only (same as +merge_fragments(paths)[:blob]+).
      # Uses a balanced binary tree of +merge_two+ calls (depth O(log k) for k shards) so work stays
      # linear in total key count across merges; +merge_two+ is associative.
      def merge_files(paths)
        merge_fragments(paths)[:blob]
      end

      # Returns +{ blob:, meta:, groups: }+ where +groups+ is recomputed from merged blob when fragments
      # include +meta.polyrun_coverage_root+ and +meta.polyrun_coverage_groups+ (emitted by {Collector}).
      # When +meta.polyrun_track_files+ is present (sharded runs defer per-shard untracked expansion),
      # applies +TrackFiles.merge_untracked_into_blob+ once on the merged blob so totals match serial.
      def merge_fragments(paths)
        return {blob: {}, meta: {}, groups: nil} if paths.empty?

        docs = paths.map { |p| JSON.parse(File.read(p)) }
        blobs = docs.map { |d| extract_coverage_blob(d) }
        merged_blob = merge_blob_tree(blobs)
        merged_meta = merge_fragment_metas(docs)
        merged_blob = apply_track_files_once_after_merge(merged_blob, merged_meta)
        groups_payload = recompute_groups_from_meta(merged_blob, merged_meta)
        {blob: merged_blob, meta: merged_meta, groups: groups_payload}
      end

      def apply_track_files_once_after_merge(blob, merged_meta)
        return blob unless merged_meta.is_a?(Hash)

        tf = merged_meta["polyrun_track_files"]
        root = merged_meta["polyrun_coverage_root"]
        return blob if tf.nil? || root.nil?

        require_relative "track_files"
        TrackFiles.merge_untracked_into_blob(blob, root, tf)
      end

      # Balanced reduction: same total +merge_two+ work as a left fold, shallower call stack.
      def merge_blob_tree(blobs)
        return {} if blobs.empty?
        return blobs.first if blobs.size == 1

        list = blobs.dup
        while list.size > 1
          nxt = []
          i = 0
          while i < list.size
            if i + 1 < list.size
              nxt << merge_two(list[i], list[i + 1])
              i += 2
            else
              nxt << list[i]
              i += 1
            end
          end
          list = nxt
        end
        list.first
      end

      INTERNAL_META_KEYS = %w[polyrun_coverage_root polyrun_coverage_groups polyrun_track_files].freeze

      def normalize_track_files_meta(tf)
        case tf
        when Array then tf.map(&:to_s).sort
        else [tf.to_s]
        end
      end

      def recompute_groups_from_meta(blob, merged_meta)
        return nil unless merged_meta.is_a?(Hash)

        r = merged_meta["polyrun_coverage_root"]
        g = merged_meta["polyrun_coverage_groups"]
        return nil if r.nil? || g.nil? || g.empty?

        require_relative "track_files"
        TrackFiles.group_summaries(blob, r, g)
      end

      def parse_file(path)
        text = File.read(path)
        data = JSON.parse(text)
        extract_coverage_blob(data)
      end

      # Picks top-level export `coverage`, merges all suite entries (e.g. RSpec + Minitest),
      # and combines both when present.
      def extract_coverage_blob(data)
        return {} unless data.is_a?(Hash)

        top = data["coverage"]
        nested = []
        data.each do |k, v|
          next if k == "coverage"
          next unless v.is_a?(Hash) && v["coverage"].is_a?(Hash)

          nested << v["coverage"]
        end

        if nested.empty?
          return top if top.is_a?(Hash)

          return {}
        end

        merged = nested.reduce { |acc, el| merge_two(acc, el) }
        top.is_a?(Hash) ? merge_two(top, merged) : merged
      end
    end
  end
end

require_relative "merge_merge_two"
require_relative "merge_fragment_meta"
require_relative "merge/formatters"
