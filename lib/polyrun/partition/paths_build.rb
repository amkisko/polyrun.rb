require "fileutils"
require "pathname"
require "set"

module Polyrun
  module Partition
    # Writes +partition.paths_file+ from +partition.paths_build+
    module PathsBuild
      module_function

      # @return [Integer] 0 on success or skip, 2 on configuration error
      def apply!(partition:, cwd: Dir.pwd)
        return 0 if skip_paths_build?

        pb = partition["paths_build"] || partition[:paths_build]
        return 0 unless pb.is_a?(Hash) && !pb.empty?

        paths_file = (partition["paths_file"] || partition[:paths_file] || "spec/spec_paths.txt").to_s
        out_abs = File.expand_path(paths_file, cwd)
        lines = build_ordered_paths(pb, cwd)
        FileUtils.mkdir_p(File.dirname(out_abs))
        File.write(out_abs, lines.join("\n") + "\n")
        Polyrun::Log.warn "polyrun paths-build: wrote #{lines.size} path(s) → #{paths_file}"
        0
      rescue Polyrun::Error => e
        Polyrun::Log.warn "polyrun paths-build: #{e.message}"
        2
      end

      def skip_paths_build?
        v = ENV["POLYRUN_SKIP_PATHS_BUILD"].to_s.downcase
        %w[1 true yes].include?(v)
      end

      # Builds ordered path strings relative to +cwd+ (forward slashes).
      def build_ordered_paths(pb, cwd)
        pb = stringify_keys(pb)
        all_glob = pb["all_glob"].to_s
        all_glob = "spec/**/*_spec.rb" if all_glob.empty?

        pool = glob_under_cwd(all_glob, cwd)
        pool.uniq!
        stages = Array(pb["stages"])
        return sort_paths(pool) if stages.empty?

        apply_stages_to_pool(stages, pool, cwd)
      end

      def apply_stages_to_pool(stages, pool, cwd)
        remaining = Set.new(pool)
        out = []
        stages.each do |raw|
          st = stringify_keys(raw)
          taken =
            if st["glob"]
              take_glob_paths(st, remaining, cwd)
            elsif st["regex"]
              take_regex_paths(st, remaining)
            else
              raise Polyrun::Error, 'paths_build stage needs "glob" or "regex"'
            end
          out.concat(taken)
          remaining.subtract(taken)
        end
        out.concat(sort_paths(remaining.to_a))
        out
      end

      def take_glob_paths(st, remaining, cwd)
        taken = glob_under_cwd(st["glob"].to_s, cwd).select { |p| remaining.include?(p) }
        if st["sort_by_substring_order"]
          subs = Array(st["sort_by_substring_order"]).map(&:to_s)
          def_prio = int_or(st["default_priority"], int_or(st["default_sort_key"], 99))
          taken.sort_by! { |p| [substring_priority(p, subs, def_prio), p] }
        else
          sort_paths!(taken)
        end
        taken
      end

      def take_regex_paths(st, remaining)
        ic = st["ignore_case"]
        ignore_case = ic == true || %w[1 true yes].include?(ic.to_s.downcase)
        rx = Regexp.new(st["regex"].to_s, ignore_case ? Regexp::IGNORECASE : 0)
        taken = remaining.to_a.select { |p| rx.match?(p) || rx.match?(File.basename(p)) }
        sort_paths!(taken)
        taken
      end

      def glob_under_cwd(pattern, cwd)
        root = File.expand_path(cwd)
        Dir.glob(File.join(root, pattern)).map { |p| normalize_rel(p, cwd) }
      end

      def normalize_rel(path, cwd)
        abs = File.expand_path(path, cwd)
        Pathname.new(abs).relative_path_from(Pathname.new(File.expand_path(cwd))).to_s.tr("\\", "/")
      end

      def sort_paths(paths)
        paths.sort
      end

      def sort_paths!(paths)
        paths.sort!
      end

      def substring_priority(path, substrings, default)
        substrings.each_with_index do |s, i|
          return i if path.include?(s)
        end
        default
      end

      def stringify_keys(h)
        return {} unless h.is_a?(Hash)

        h.each_with_object({}) { |(k, v), o| o[k.to_s] = v }
      end

      def int_or(v, fallback)
        Integer(v)
      rescue ArgumentError, TypeError
        fallback
      end
    end
  end
end
