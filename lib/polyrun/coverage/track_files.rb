require "pathname"

require_relative "merge"

module Polyrun
  module Coverage
    # SimpleCov-compatible +track_files+ (globs from project root) and +add_group+ statistics
    # for the JSON payload (+groups+ with +lines.covered_percent+ per group).
    module TrackFiles
      module_function

      # Expands one or more glob patterns relative to +root+ (supports +{a,b}/**/*.rb+ with File::FNM_EXTGLOB).
      def expand_globs(root, track_files)
        root = File.expand_path(root)
        patterns = Array(track_files).map(&:to_s).reject(&:empty?)
        return [] if patterns.empty?

        patterns.flat_map do |pattern|
          Dir.chdir(root) do
            Dir.glob(pattern, File::FNM_EXTGLOB)
          end
        end.map { |rel| File.expand_path(rel, root) }.uniq
      end

      # Adds tracked files that were never required, with simulated line arrays (blank/comment => nil, else 0).
      # Matches SimpleCov +add_not_loaded_files+ behavior for coverage completeness.
      def merge_untracked_into_blob(blob, root, track_files)
        root = File.expand_path(root)
        out = {}
        blob.each do |k, v|
          out[File.expand_path(k.to_s)] = v
        end

        expand_globs(root, track_files).each do |abs|
          next if out.key?(abs)
          next unless File.file?(abs)

          out[abs] = {"lines" => simulated_lines_for_unloaded(abs)}
        end
        out
      end

      def simulated_lines_for_unloaded(path)
        lines = []
        File.foreach(path) do |line|
          lines << (blank_or_comment?(line) ? nil : 0)
        end
        lines
      rescue Errno::ENOENT, Errno::EACCES
        []
      end

      def blank_or_comment?(line)
        s = line.strip
        s.empty? || s.start_with?("#")
      end

      # +groups+ is a Hash of group_name => glob pattern (relative to +root+), SimpleCov +add_group+ style.
      # Produces the +groups+ section of SimpleCov JSON: each group has lines.covered_percent.
      # Assignment uses paths present in +blob+ matching each glob (+File.fnmatch?+), not a fresh Dir.glob,
      # so in-memory coverage lines up with reported files. Files matching no group get "Ungrouped".
      def group_summaries(blob, root, groups)
        return {} if groups.nil? || groups.empty?

        root = File.expand_path(root)
        normalized = {}
        blob.each { |k, v| normalized[File.expand_path(k.to_s)] = v }

        accum, ungrouped, any_ungrouped = group_summaries_accumulate(normalized, root, groups)
        group_summaries_build_payload(groups, accum, ungrouped, any_ungrouped)
      end

      def group_summaries_accumulate(normalized, root, groups)
        accum = Hash.new { |h, k| h[k] = {relevant: 0, covered: 0} }
        ungrouped = {relevant: 0, covered: 0}
        any_ungrouped_file = false

        normalized.each do |abs, entry|
          counts = Merge.line_counts(entry)
          matched = []
          groups.each do |name, glob_pattern|
            matched << name.to_s if file_matches_glob?(abs, glob_pattern, root)
          end
          if matched.empty?
            any_ungrouped_file = true
            ungrouped[:relevant] += counts[:relevant]
            ungrouped[:covered] += counts[:covered]
          else
            matched.each { |n| add_counts!(accum[n], counts) }
          end
        end
        [accum, ungrouped, any_ungrouped_file]
      end

      def group_summaries_build_payload(groups, accum, ungrouped, any_ungrouped_file)
        out = {}
        groups.each_key do |name|
          n = name.to_s
          a = accum[n]
          out[n] = {
            "lines" => {
              "covered_percent" => percent_from_counts(a[:relevant], a[:covered])
            }
          }
        end

        if any_ungrouped_file
          out["Ungrouped"] = {
            "lines" => {
              "covered_percent" => percent_from_counts(ungrouped[:relevant], ungrouped[:covered])
            }
          }
        end

        out
      end

      def add_counts!(acc, delta)
        acc[:relevant] += delta[:relevant]
        acc[:covered] += delta[:covered]
      end

      def percent_from_counts(relevant, covered)
        return round_percent(0.0) if relevant <= 0

        round_percent(100.0 * covered / relevant)
      end

      def file_matches_glob?(absolute_path, pattern, root)
        rel = Pathname.new(absolute_path).relative_path_from(Pathname.new(root)).to_s
        File.fnmatch?(pattern, rel, File::FNM_PATHNAME | File::FNM_EXTGLOB)
      rescue ArgumentError
        File.fnmatch?(pattern, absolute_path, File::FNM_PATHNAME | File::FNM_EXTGLOB)
      end

      def round_percent(x)
        x.to_f.round(2)
      end
    end
  end
end
