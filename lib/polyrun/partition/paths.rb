module Polyrun
  module Partition
    # Shared spec path listing for run-shards, queue init, and plan helpers.
    module Paths
      module_function

      def read_lines(path)
        File.read(File.expand_path(path.to_s, Dir.pwd)).split("\n").map(&:strip).reject(&:empty?)
      end

      # Prefer +spec/+ RSpec files, then +test/+ Minitest, then Polyrun Quick files (same globs as +polyrun quick+).
      # Order avoids running the broader Quick glob when RSpec or Minitest files already exist.
      def detect_auto_suite(cwd = Dir.pwd)
        base = File.expand_path(cwd)
        return :rspec if Dir.glob(File.join(base, "spec/**/*_spec.rb")).any?

        return :minitest if Dir.glob(File.join(base, "test/**/*_test.rb")).any?

        quick = quick_parallel_default_paths(base)
        return :quick if quick.any?

        nil
      end

      # Infer parallel suite from explicit paths (+_spec.rb+ vs +_test.rb+ vs Polyrun quick-style +.rb+).
      # Recognizes RSpec-style +path:line+ locators (strips a trailing numeric locator before classifying).
      # Returns +:rspec+, +:minitest+, +:quick+, +:invalid+ (mixed spec and test), or +nil+ (empty).
      def infer_suite_from_paths(paths)
        paths = Array(paths).map { |p| suite_classify_path(p) }
        return nil if paths.empty?

        specs = paths.count { |p| File.basename(p).end_with?("_spec.rb") }
        tests = paths.count { |p| File.basename(p).end_with?("_test.rb") }
        return :invalid if specs.positive? && tests.positive?

        return :rspec if specs.positive?
        return :minitest if tests.positive?

        others = paths.size - specs - tests
        return :quick if others.positive?

        nil
      end

      # When +paths_file+ is set but missing, returns +{ error: "..." }+.
      # Otherwise returns +{ items:, source: }+ (human-readable source label).
      #
      # +partition.suite+ (optional): +auto+ (default), +rspec+, +minitest+, +quick+ — used when resolving
      # from globs. Legacy +spec/spec_paths.txt+ is used only for +auto+/+rspec+ (RSpec-oriented); an
      # explicit +minitest+/+quick+ suite skips it and globs instead. Bare +polyrun+ suite selection is
      # {Suite.resolve_default} (explicit suite → paths_file inference → {detect_auto_suite}).
      def resolve_run_shard_items(paths_file: nil, cwd: Dir.pwd, partition: {})
        if paths_file
          abs = File.expand_path(paths_file.to_s, cwd)
          unless File.file?(abs)
            return {error: "paths file not found: #{abs}"}
          end
          {items: read_lines(abs), source: paths_file.to_s}
        elsif use_legacy_spec_paths?(cwd, partition)
          {items: read_lines(File.join(cwd, "spec", "spec_paths.txt")), source: "spec/spec_paths.txt"}
        else
          resolve_run_shard_items_glob(cwd: cwd, partition: partition)
        end
      end

      def resolve_run_shard_items_glob(cwd:, partition: {})
        suite = (partition["suite"] || partition[:suite] || "auto").to_s.downcase
        suite = "auto" if suite.empty?

        base = File.expand_path(cwd)
        spec = Dir.glob(File.join(base, "spec/**/*_spec.rb")).sort
        test = Dir.glob(File.join(base, "test/**/*_test.rb")).sort
        quick = quick_parallel_default_paths(base)

        case suite
        when "rspec"
          return {error: "partition.suite is rspec but no spec/**/*_spec.rb files"} if spec.empty?

          {items: spec, source: "spec/**/*_spec.rb glob"}
        when "minitest"
          return {error: "partition.suite is minitest but no test/**/*_test.rb files"} if test.empty?

          {items: test, source: "test/**/*_test.rb glob"}
        when "quick"
          return {error: "partition.suite is quick but no Polyrun quick files under spec/ or test/"} if quick.empty?

          {items: quick, source: "Polyrun quick glob"}
        when "auto"
          if spec.any?
            {items: spec, source: "spec/**/*_spec.rb glob"}
          elsif test.any?
            {items: test, source: "test/**/*_test.rb glob"}
          elsif quick.any?
            {items: quick, source: "Polyrun quick glob"}
          else
            {
              error: "no spec paths (spec/spec_paths.txt, partition.paths_file, or spec/**/*_spec.rb); " \
                     "no test/**/*_test.rb; no Polyrun quick files"
            }
          end
        else
          {error: "unknown partition.suite: #{suite.inspect} (expected auto, rspec, minitest, quick)"}
        end
      end

      def quick_parallel_default_paths(base)
        require_relative "../quick/runner"
        Polyrun::Quick::Runner.parallel_default_paths(base)
      end

      # Strip trailing numeric locators (+path:line+ or +path:line:column+), then expand.
      def suite_classify_path(path)
        raw = path.to_s.sub(/(?::\d+)+\z/, "")
        File.expand_path(raw)
      end
      private_class_method :suite_classify_path

      def use_legacy_spec_paths?(cwd, partition)
        return false unless File.file?(File.join(cwd, "spec", "spec_paths.txt"))

        suite = (partition["suite"] || partition[:suite] || "auto").to_s.downcase
        suite = "auto" if suite.empty?
        %w[auto rspec].include?(suite)
      end
      private_class_method :use_legacy_spec_paths?
    end
  end
end
