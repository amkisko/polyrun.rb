module Polyrun
  module Partition
    # Shared spec path listing for run-shards, queue init, and plan helpers.
    module Paths
      SUS_CONFIG_REL = "config/sus.rb"
      SUS_TEST_GLOB = "test/**/*.rb"

      module_function

      def read_lines(path)
        File.read(File.expand_path(path.to_s, Dir.pwd)).split("\n").map(&:strip).reject(&:empty?)
      end

      # Prefer +spec/+ RSpec files, then Sus (+config/sus.rb+ + +test/**/*.rb+), then +test/+ Minitest,
      # then Polyrun Quick files (same globs as +polyrun quick+).
      def detect_auto_suite(cwd = Dir.pwd)
        base = File.expand_path(cwd)
        return :rspec if Dir.glob(File.join(base, "spec/**/*_spec.rb")).any?

        sus = sus_test_paths(base)
        return :sus if sus_configured?(base) && sus.any?

        return :minitest if Dir.glob(File.join(base, "test/**/*_test.rb")).any?

        quick = quick_parallel_default_paths(base)
        return :quick if quick.any?

        nil
      end

      # Infer parallel suite from explicit paths.
      # Recognizes RSpec-style +path:line+ locators (strips a trailing numeric locator before classifying).
      # Returns +:rspec+, +:minitest+, +:sus+, +:quick+, +:invalid+ (mixed families), or +nil+ (empty).
      def infer_suite_from_paths(paths)
        families = Array(paths).map { |p| suite_family_for_path(p) }.compact
        return nil if families.empty?

        uniq = families.uniq
        return :invalid if uniq.size > 1

        uniq.first
      end

      # When +paths_file+ is set but missing, returns +{ error: "..." }+.
      # Otherwise returns +{ items:, source: }+ (human-readable source label).
      #
      # +partition.suite+ (optional): +auto+ (default), +rspec+, +minitest+, +sus+, +quick+ — used when resolving
      # from globs. Legacy +spec/spec_paths.txt+ is used only for +auto+/+rspec+ (RSpec-oriented); an
      # explicit +minitest+/+sus+/+quick+ suite skips it and globs instead. Bare +polyrun+ suite selection is
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
        suite = partition_suite_name(partition)
        catalogs = shard_path_catalogs(File.expand_path(cwd))
        case suite
        when "rspec", "minitest", "sus", "quick"
          resolve_named_suite_items(suite, catalogs)
        when "auto"
          resolve_auto_suite_items(catalogs)
        else
          {error: "unknown partition.suite: #{suite.inspect} (expected auto, rspec, minitest, sus, quick)"}
        end
      end

      def partition_suite_name(partition)
        suite = (partition["suite"] || partition[:suite] || "auto").to_s.downcase
        suite.empty? ? "auto" : suite
      end
      private_class_method :partition_suite_name

      def shard_path_catalogs(base)
        {
          base: base,
          spec: Dir.glob(File.join(base, "spec/**/*_spec.rb")).sort,
          test: Dir.glob(File.join(base, "test/**/*_test.rb")).sort,
          sus: sus_test_paths(base),
          quick: quick_parallel_default_paths(base)
        }
      end
      private_class_method :shard_path_catalogs

      def resolve_named_suite_items(suite, catalogs)
        case suite
        when "rspec"
          return {error: "partition.suite is rspec but no spec/**/*_spec.rb files"} if catalogs[:spec].empty?

          {items: catalogs[:spec], source: "spec/**/*_spec.rb glob"}
        when "minitest"
          return {error: "partition.suite is minitest but no test/**/*_test.rb files"} if catalogs[:test].empty?

          {items: catalogs[:test], source: "test/**/*_test.rb glob"}
        when "sus"
          return {error: "partition.suite is sus but no test/**/*.rb files"} if catalogs[:sus].empty?

          {items: catalogs[:sus], source: "test/**/*.rb glob (sus)"}
        else
          return {error: "partition.suite is quick but no Polyrun quick files under spec/ or test/"} if catalogs[:quick].empty?

          {items: catalogs[:quick], source: "Polyrun quick glob"}
        end
      end
      private_class_method :resolve_named_suite_items

      def resolve_auto_suite_items(catalogs)
        if catalogs[:spec].any?
          {items: catalogs[:spec], source: "spec/**/*_spec.rb glob"}
        elsif sus_configured?(catalogs[:base]) && catalogs[:sus].any?
          {items: catalogs[:sus], source: "test/**/*.rb glob (sus)"}
        elsif catalogs[:test].any?
          {items: catalogs[:test], source: "test/**/*_test.rb glob"}
        elsif catalogs[:quick].any?
          {items: catalogs[:quick], source: "Polyrun quick glob"}
        else
          {
            error: "no spec paths (spec/spec_paths.txt, partition.paths_file, or spec/**/*_spec.rb); " \
                   "no Sus test/**/*.rb (with config/sus.rb); no test/**/*_test.rb; no Polyrun quick files"
          }
        end
      end
      private_class_method :resolve_auto_suite_items

      def quick_parallel_default_paths(base)
        require_relative "../quick/runner"
        Polyrun::Quick::Runner.parallel_default_paths(base)
      end

      def sus_configured?(base)
        File.file?(File.join(base, SUS_CONFIG_REL))
      end

      def sus_test_paths(base)
        Dir.glob(File.join(base, SUS_TEST_GLOB)).sort
      end

      # Strip trailing numeric locators (+path:line+ or +path:line:column+), then expand.
      def suite_classify_path(path)
        raw = path.to_s.sub(/(?::\d+)+\z/, "")
        File.expand_path(raw)
      end
      private_class_method :suite_classify_path

      def suite_family_for_path(path)
        abs = suite_classify_path(path)
        base = File.basename(abs)
        return :rspec if base.end_with?("_spec.rb")
        return :minitest if base.end_with?("_test.rb")
        return :quick if abs.include?("polyrun_quick")
        return :sus if abs.match?(%r{(?:^|/)test/})

        :quick
      end
      private_class_method :suite_family_for_path

      def use_legacy_spec_paths?(cwd, partition)
        return false unless File.file?(File.join(cwd, "spec", "spec_paths.txt"))

        %w[auto rspec].include?(partition_suite_name(partition))
      end
      private_class_method :use_legacy_spec_paths?
    end
  end
end
