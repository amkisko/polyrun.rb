module Polyrun
  module Coverage
    module Merge
      module_function

      def merge_two(a, b)
        keys = a.keys | b.keys
        out = {}
        keys.each do |path|
          out[path] = merge_file_entry(a[path], b[path])
        end
        out
      end

      def normalize_file_entry(v)
        return nil if v.nil?
        return {"lines" => v} if v.is_a?(Array)

        v
      end

      def line_array_from_file_entry(file)
        h = normalize_file_entry(file)
        return nil unless h.is_a?(Hash)

        h["lines"] || h[:lines]
      end

      def merge_file_entry(x, y)
        x = normalize_file_entry(x)
        y = normalize_file_entry(y)
        return y if x.nil?
        return x if y.nil?

        lines = merge_line_arrays(x["lines"] || x[:lines], y["lines"] || y[:lines])
        entry = {"lines" => lines}
        bx = x["branches"] || x[:branches]
        by = y["branches"] || y[:branches]
        br = merge_branch_arrays(bx, by)
        entry["branches"] = br if br
        entry
      end

      def merge_line_arrays(a, b)
        a ||= []
        b ||= []
        na = a.size
        nb = b.size
        max_len = (na > nb) ? na : nb
        out = Array.new(max_len)
        i = 0
        while i < max_len
          out[i] = merge_line_hits(a[i], b[i])
          i += 1
        end
        out
      end

      def merge_line_hits(x, y)
        return y if x.nil?
        return x if y.nil?
        return "ignored" if x == "ignored" || y == "ignored"

        xi = line_hit_to_i(x)
        yi = line_hit_to_i(y)
        return xi + yi if xi && yi

        return yi if xi.nil? && yi
        return xi if yi.nil? && xi

        x
      end

      def line_hit_to_i(v)
        case v
        when Integer then v
        when nil then nil
        else
          Integer(v, exception: false)
        end
      end

      def merge_branch_arrays(a, b)
        return nil if a.nil? && b.nil?
        return (a || b).dup if a.nil? || b.nil?

        index = {}
        [a, b].each do |arr|
          arr.each do |br|
            k = branch_key(br)
            existing = index[k]
            index[k] =
              if existing
                merge_branch_entries(existing, br)
              else
                br.dup
              end
          end
        end
        index.values.sort_by { |br| branch_key(br) }
      end

      def branch_key(br)
        h = br.is_a?(Hash) ? br : {}
        [h["type"] || h[:type], h["start_line"] || h[:start_line], h["end_line"] || h[:end_line]]
      end

      def merge_branch_entries(x, y)
        out = x.is_a?(Hash) ? x.dup : {}
        xc = (x["coverage"] || x[:coverage]).to_i
        yc = (y["coverage"] || y[:coverage]).to_i
        out["coverage"] = xc + yc
        out
      end
    end
  end
end
