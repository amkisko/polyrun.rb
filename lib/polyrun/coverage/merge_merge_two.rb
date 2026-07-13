module Polyrun
  module Coverage
    module Merge
      module_function

      def merge_two(a, b)
        if native_acceleration?
          MergeNative.merge_two(a, b)
        else
          merge_two_ruby(a, b)
        end
      end

      def merge_two_ruby(a, b)
        a = {} if a.nil?
        b = {} if b.nil?
        if a.size >= b.size
          merge_two_by_keys(a, b)
        else
          merge_two_by_keys(b, a)
        end
      end

      def merge_two_by_keys(primary, secondary)
        out = {}
        primary.each do |path, entry|
          out[path] = merge_file_entry(entry, secondary[path])
        end
        secondary.each do |path, entry|
          out[path] = entry unless out.key?(path)
        end
        out
      end

      def native_merge_line_arrays?
        native_acceleration?
      end

      def native_acceleration?
        MergeNative.available?
      end

      def normalize_file_entry(value)
        return nil if value.nil?
        return {"lines" => value} if value.is_a?(Array)

        value
      end

      def line_array_from_file_entry(file)
        hash = normalize_file_entry(file)
        return nil unless hash.is_a?(Hash)

        hash["lines"] || hash[:lines]
      end

      def merge_file_entry(left, right)
        left = normalize_file_entry(left)
        right = normalize_file_entry(right)
        return right if left.nil?
        return left if right.nil?

        lines = merge_line_arrays(left["lines"] || left[:lines], right["lines"] || right[:lines])
        entry = {"lines" => lines}
        left_branches = left["branches"] || left[:branches]
        right_branches = right["branches"] || right[:branches]
        branches = merge_branch_arrays(left_branches, right_branches)
        entry["branches"] = branches if branches
        entry
      end

      def merge_line_arrays(left, right)
        if native_acceleration?
          MergeNative.merge_line_arrays(left, right)
        else
          merge_line_arrays_ruby(left, right)
        end
      end

      def merge_line_arrays_ruby(left, right)
        left ||= []
        right ||= []
        left_size = left.size
        right_size = right.size
        max_len = (left_size > right_size) ? left_size : right_size
        out = Array.new(max_len)
        index = 0
        while index < max_len
          out[index] = merge_line_hits(left[index], right[index])
          index += 1
        end
        out
      end

      def merge_line_hits(left, right)
        return right if left.nil?
        return left if right.nil?
        return "ignored" if left == "ignored" || right == "ignored"

        left_i = line_hit_to_i(left)
        right_i = line_hit_to_i(right)
        return left_i + right_i if left_i && right_i

        return right_i if left_i.nil? && right_i
        return left_i if right_i.nil? && left_i

        left
      end

      def line_hit_to_i(value)
        case value
        when Integer then value
        when nil then nil
        else
          Integer(value, exception: false)
        end
      end

      def merge_branch_arrays(left, right)
        return nil if left.nil? && right.nil?
        return (left || right).dup if left.nil? || right.nil?

        index = {}
        [left, right].each do |array|
          array.each do |branch|
            next unless branch.is_a?(Hash)

            key = branch_key(branch)
            existing = index[key]
            index[key] =
              if existing
                merge_branch_entries(existing, branch)
              else
                branch.dup
              end
          end
        end
        index.values.sort_by { |branch| branch_key(branch) }
      end

      def branch_key(branch)
        hash = branch.is_a?(Hash) ? branch : {}
        [hash["type"] || hash[:type], hash["start_line"] || hash[:start_line], hash["end_line"] || hash[:end_line]]
      end

      def merge_branch_arrays_for_native(left, right)
        merge_branch_arrays(left, right)
      end

      def sort_branches_for_native(branches)
        branches.sort_by { |branch| branch_key(branch) }
      end

      def merge_branch_entries(left, right)
        out = left.is_a?(Hash) ? left.dup : {}
        left_count = (left["coverage"] || left[:coverage]).to_i
        right_count = (right["coverage"] || right[:coverage]).to_i
        out["coverage"] = left_count + right_count
        out
      end
    end
  end
end

require_relative "merge_native"
Polyrun::Coverage::MergeNative.load!
