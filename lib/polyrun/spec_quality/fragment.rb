require "fileutils"

require "json"

module Polyrun
  module SpecQuality
    module Fragment
      module_function

      def default_fragment_path(env = ENV)
        dir = env.fetch("POLYRUN_SPEC_QUALITY_FRAGMENT_DIR", default_fragment_dir)
        base = Polyrun::Coverage::CollectorFragmentMeta.fragment_default_basename_from_env(env)
        File.expand_path(File.join(dir, "polyrun-spec-quality-fragment-#{base}.jsonl"))
      end

      def default_fragment_dir
        File.join(Dir.pwd, "coverage")
      end

      def glob_pattern(cwd = Dir.pwd)
        File.join(cwd, "coverage", "polyrun-spec-quality-fragment-*.jsonl")
      end

      def ensure_fragment_dir!(path)
        FileUtils.mkdir_p(File.dirname(path))
      end

      def truncate_fragment!(path)
        ensure_fragment_dir!(path)
        File.write(path, "")
      end

      def append_row!(path, row)
        ensure_fragment_dir!(path)
        File.open(path, "a") { |f| f.puts(JSON.generate(row)) }
      end
    end
  end
end
