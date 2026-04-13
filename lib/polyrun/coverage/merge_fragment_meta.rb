module Polyrun
  module Coverage
    module Merge
      module_function

      def merge_fragment_metas(docs)
        metas = docs.map { |d| extract_doc_meta(d) }
        base = metas.first.dup
        roots = metas.map { |m| m["polyrun_coverage_root"] }.compact
        grs = metas.map { |m| m["polyrun_coverage_groups"] }.compact
        tfs = metas.map { |m| m["polyrun_track_files"] }.compact
        merge_fragment_meta_warn_root!(roots)
        merge_fragment_meta_warn_groups!(grs)
        merge_fragment_meta_warn_track_files!(tfs)
        root = roots.first
        groups_cfg = grs.first
        track_files_cfg = tfs.first
        base["polyrun_coverage_root"] = root if root
        base["polyrun_coverage_groups"] = groups_cfg if groups_cfg
        base["polyrun_track_files"] = track_files_cfg if track_files_cfg
        base
      end

      def extract_doc_meta(d)
        (d.is_a?(Hash) && d["meta"].is_a?(Hash)) ? d["meta"].transform_keys(&:to_s) : {}
      end

      def merge_fragment_meta_warn_root!(roots)
        return if roots.uniq.size <= 1

        Polyrun::Log.warn "Polyrun merge-coverage: polyrun_coverage_root differs across fragments; using first."
      end

      def merge_fragment_meta_warn_groups!(grs)
        return if grs.uniq.size <= 1

        Polyrun::Log.warn "Polyrun merge-coverage: polyrun_coverage_groups differs across fragments; using first."
      end

      def merge_fragment_meta_warn_track_files!(tfs)
        return if tfs.map { |tf| JSON.generate(normalize_track_files_meta(tf)) }.uniq.size <= 1

        Polyrun::Log.warn "Polyrun merge-coverage: polyrun_track_files differs across fragments; using first."
      end
    end
  end
end
