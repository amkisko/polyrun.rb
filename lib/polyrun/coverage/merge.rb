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

      def merge_fragment_metas(docs)
        metas = docs.map do |d|
          (d.is_a?(Hash) && d["meta"].is_a?(Hash)) ? d["meta"].transform_keys(&:to_s) : {}
        end
        base = metas.first.dup
        roots = metas.map { |m| m["polyrun_coverage_root"] }.compact
        grs = metas.map { |m| m["polyrun_coverage_groups"] }.compact
        tfs = metas.map { |m| m["polyrun_track_files"] }.compact
        root = roots.first
        groups_cfg = grs.first
        track_files_cfg = tfs.first
        if roots.uniq.size > 1
          Polyrun::Log.warn "Polyrun merge-coverage: polyrun_coverage_root differs across fragments; using first."
        end
        if grs.uniq.size > 1
          Polyrun::Log.warn "Polyrun merge-coverage: polyrun_coverage_groups differs across fragments; using first."
        end
        if tfs.map { |tf| JSON.generate(normalize_track_files_meta(tf)) }.uniq.size > 1
          Polyrun::Log.warn "Polyrun merge-coverage: polyrun_track_files differs across fragments; using first."
        end
        base["polyrun_coverage_root"] = root if root
        base["polyrun_coverage_groups"] = groups_cfg if groups_cfg
        base["polyrun_track_files"] = track_files_cfg if track_files_cfg
        base
      end

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

      def merge_two(a, b)
        # Array#| is set union without the extra array from concat + uniq.
        keys = a.keys | b.keys
        out = {}
        keys.each do |path|
          out[path] = merge_file_entry(a[path], b[path])
        end
        out
      end

      # SimpleCov pre-0.18 and some exports store a file as a raw line array; modern shape uses {"lines"=>[...]}.
      # Research: spec3.md (SimpleCov format drift); merge tolerates both.
      def normalize_file_entry(v)
        return nil if v.nil?
        return {"lines" => v} if v.is_a?(Array)

        v
      end

      def line_array_from_file_entry(file)
        h = normalize_file_entry(file)
        return nil unless h.is_a?(Hash)

        h["lines"] || h[:lines]
      end

      def merge_file_entry(x, y)
        x = normalize_file_entry(x)
        y = normalize_file_entry(y)
        return y if x.nil?
        return x if y.nil?

        lines = merge_line_arrays(x["lines"] || x[:lines], y["lines"] || y[:lines])
        entry = {"lines" => lines}
        bx = x["branches"] || x[:branches]
        by = y["branches"] || y[:branches]
        br = merge_branch_arrays(bx, by)
        entry["branches"] = br if br
        entry
      end

      def merge_line_arrays(a, b)
        a ||= []
        b ||= []
        na = a.size
        nb = b.size
        max_len = (na > nb) ? na : nb
        out = Array.new(max_len)
        i = 0
        while i < max_len
          out[i] = merge_line_hits(a[i], b[i])
          i += 1
        end
        out
      end

      def merge_line_hits(x, y)
        return y if x.nil?
        return x if y.nil?
        return "ignored" if x == "ignored" || y == "ignored"

        xi = line_hit_to_i(x)
        yi = line_hit_to_i(y)
        return xi + yi if xi && yi

        return yi if xi.nil? && yi
        return xi if yi.nil? && xi

        x
      end

      def line_hit_to_i(v)
        case v
        when Integer then v
        when nil then nil
        else
          Integer(v, exception: false)
        end
      end

      def merge_branch_arrays(a, b)
        return nil if a.nil? && b.nil?
        return (a || b).dup if a.nil? || b.nil?

        index = {}
        [a, b].each do |arr|
          arr.each do |br|
            k = branch_key(br)
            existing = index[k]
            index[k] =
              if existing
                merge_branch_entries(existing, br)
              else
                br.dup
              end
          end
        end
        index.values.sort_by { |br| branch_key(br) }
      end

      def branch_key(br)
        h = br.is_a?(Hash) ? br : {}
        [h["type"] || h[:type], h["start_line"] || h[:start_line], h["end_line"] || h[:end_line]]
      end

      def merge_branch_entries(x, y)
        out = x.is_a?(Hash) ? x.dup : {}
        xc = (x["coverage"] || x[:coverage]).to_i
        yc = (y["coverage"] || y[:coverage]).to_i
        out["coverage"] = xc + yc
        out
      end
    end
  end
end

require_relative "merge/formatters"
