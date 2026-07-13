module Polyrun
  module Coverage
    module ExampleDiff
      # Sparse line-hit snapshots for per-example diff storage.
      module Snapshot
        module_function

        def sparse_snapshot_lines(lines)
          {"sparse" => true, "hits" => dense_hits_map(lines)}
        end

        def hits_map(entry)
          return {} if entry.nil?

          if entry.is_a?(Hash) && entry["sparse"]
            entry["hits"] || {}
          else
            dense_hits_map(ExampleDiff.line_array(entry))
          end
        end

        def dense_hits_map(lines)
          hits = {}
          lines.each_with_index do |value, index|
            stored = snapshot_line_value(value)
            hits[index] = stored unless stored.nil?
          end
          hits
        end

        def snapshot_line_value(value)
          case value
          when nil then nil
          when "ignored" then "ignored"
          when Integer then value
          else
            parsed = Integer(value, exception: false)
            parsed.nil? ? value : parsed
          end
        end
      end
    end
  end
end
