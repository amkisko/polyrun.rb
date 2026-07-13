module Polyrun
  module Coverage
    module MergeNative
      module_function

      def load!
        return true if available?

        extension_dir = File.expand_path("../../../ext/polyrun_coverage_merge", __dir__)
        if File.directory?(extension_dir)
          $LOAD_PATH.unshift(extension_dir) unless $LOAD_PATH.include?(extension_dir)
        end

        require "polyrun_coverage_merge"
        true
      rescue LoadError
        false
      end

      def available?
        ::Object.const_defined?(:PolyrunCoverageMerge)
      end

      def merge_line_arrays(left, right)
        ::PolyrunCoverageMerge.merge_line_arrays(left, right)
      end

      def merge_two(left, right)
        ::PolyrunCoverageMerge.merge_two(left, right)
      end

      def line_counts(file_entry)
        ::PolyrunCoverageMerge.line_counts(file_entry)
      end
    end
  end
end
