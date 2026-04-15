require "json"

require_relative "../debug"

module Polyrun
  module Timing
    # Merges per-shard timing JSON files (spec2 §2.4): path => wall seconds (float), or (experimental)
    # +absolute_path:line+ => seconds for per-example timing.
    # Disjoint suites: values merged by taking the maximum per path when duplicates appear.
    module Merge
      module_function

      def merge_files(paths)
        merged = {}
        paths.each do |p|
          data = JSON.parse(File.read(p))
          next unless data.is_a?(Hash)

          data.each do |file, sec|
            f = file.to_s
            t = sec.to_f
            merged[f] = merged.key?(f) ? [merged[f], t].max : t
          end
        end
        merged
      end

      def merge_and_write(paths, output_path)
        Polyrun::Debug.log_kv(merge_timing: "merge_and_write", input_count: paths.size, output_path: output_path)
        merged = Polyrun::Debug.time("Timing::Merge.merge_files") { merge_files(paths) }
        Polyrun::Debug.time("Timing::Merge.write JSON") { File.write(output_path, JSON.pretty_generate(merged)) }
        merged
      end
    end
  end
end
