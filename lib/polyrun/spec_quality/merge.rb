require "json"

module Polyrun
  module SpecQuality
    module Merge
      module_function

      def merge_files(paths)
        examples = {}
        paths.each do |path|
          merge_file_into!(examples, path)
        end
        build_merged_payload(examples, paths.size)
      end

      def merge_file_into!(examples, path)
        File.foreach(path) do |line|
          line = line.strip
          next if line.empty?

          row = JSON.parse(line)
          key = row["example"].to_s
          next if key.empty?

          examples[key] = row
        end
      end

      def build_merged_payload(examples, fragment_count)
        hot_lines = aggregate_hot_lines(examples)
        {
          "examples" => examples,
          "hot_lines" => hot_lines,
          "shard_summary" => shard_summary(examples),
          "meta" => {
            "polyrun_version" => Polyrun::VERSION,
            "fragment_count" => fragment_count,
            "example_count" => examples.size
          }
        }
      end

      def shard_summary(examples)
        by_shard = Hash.new { |h, k| h[k] = {"examples" => 0, "zero_hit" => 0, "line_churn" => 0} }
        examples.each do |_loc, row|
          shard = row["polyrun_shard_index"]
          shard = shard.nil? ? "?" : shard.to_s
          by_shard[shard]["examples"] += 1
          by_shard[shard]["zero_hit"] += 1 if row["unique_lines"].to_i.zero?
          by_shard[shard]["line_churn"] += row["line_churn"].to_i
        end
        by_shard
      end

      def aggregate_hot_lines(examples)
        by_line = Hash.new { |h, k| h[k] = {"examples" => [], "total_hits" => 0} }
        examples.each do |example_loc, row|
          Array(row["lines"]).each do |entry|
            path, line_no, delta = entry
            key = "#{path}:#{line_no}"
            by_line[key]["examples"] << example_loc
            by_line[key]["total_hits"] += delta.to_i
          end
        end
        by_line.transform_values do |v|
          v["example_count"] = v["examples"].uniq.size
          v
        end
      end

      def merge_and_write(paths, output_path)
        merged = merge_files(paths)
        File.write(output_path, JSON.pretty_generate(merged))
        merged
      end
    end
  end
end
