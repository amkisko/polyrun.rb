require "json"

require_relative "../debug"
require_relative "stats"
require_relative "variance_report"

module Polyrun
  module Timing
    module Merge
      module_function

      def merge_files(paths)
        merged = {}
        paths.each do |p|
          data = JSON.parse(File.read(p))
          next unless data.is_a?(Hash)

          data.each do |file, sec|
            f = file.to_s
            entry = sec
            merged[f] = merged.key?(f) ? Stats.merge_entries(merged[f], entry) : Stats.normalize_entry(entry)
          end
        end
        merged
      end

      def merge_and_write(paths, output_path)
        Polyrun::Debug.log_kv(merge_timing: "merge_and_write", input_count: paths.size, output_path: output_path)
        merged = Polyrun::Debug.time("Timing::Merge.merge_files") { merge_files(paths) }
        Polyrun::Debug.time("Timing::Merge.write JSON") { File.write(output_path, JSON.pretty_generate(merged)) }
        Timing::VarianceReport.emit_warnings!(merged)
        merged
      end
    end
  end
end
