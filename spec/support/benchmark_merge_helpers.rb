require "benchmark"

module BenchmarkMergeHelpers
  def log_native_ruby_ratio(label, ruby_time, native_time)
    return if native_time <= 0.0

    BenchmarkProfile.log format(
      "    %<label>s: ruby %<ruby>.4fs native %<native>.4fs speedup %<ratio>.2fx",
      label: label,
      ruby: ruby_time,
      native: native_time,
      ratio: ruby_time / native_time
    )
  end

  def build_blob(files:, lines_per_file:, random:, offset:, branches: false)
    blob = {}
    files.times do |file_index|
      path = "/project/app/models/aggregate_#{file_index}.rb"
      line_hits = Array.new(lines_per_file) do
        case random.rand(100)
        when 0 then nil
        when 1 then "ignored"
        else random.rand(0..15)
        end
      end
      line_hits.map! { |hit| hit.is_a?(Integer) ? (hit + offset) % 8 : hit }
      entry = {"lines" => line_hits}
      if branches
        entry["branches"] = Array.new(6) do |branch_index|
          {
            "type" => branch_index.even? ? "then" : "else",
            "start_line" => branch_index + 1,
            "end_line" => branch_index + 1,
            "coverage" => (random.rand(0..4) + offset + branch_index) % 5
          }
        end
      end
      blob[path] = entry
    end
    blob
  end
end
