require "json"

require_relative "formatter"
require_relative "merge"
require_relative "result"

module Polyrun
  module Coverage
    # Ready-to-use multi-format output (SimpleCov-compatible result blob), no extra gems.
    # Pass +formatter:+ for multi-formatter composition ({Formatter::MultiFormatter}, custom classes).
    module Reporting
      DEFAULT_FORMATS = %w[json lcov cobertura console html].freeze

      # Comma list for +merge-coverage+ / +run-shards --merge-coverage+ defaults (Codecov, Jenkins, HTML, etc.).
      DEFAULT_MERGE_FORMAT_LIST = DEFAULT_FORMATS.join(",").freeze

      # Writes selected formats under output_dir using basename as file prefix (e.g. polyrun-coverage.json).
      # When +formatter+ is nil, builds {Formatter.multi} from +formats+ (symbols or strings).
      def self.write(coverage_blob, output_dir:, basename: "polyrun-coverage", formats: DEFAULT_FORMATS, meta: {}, groups: nil, formatter: nil)
        fmt = formatter || Formatter.multi(*Array(formats).map(&:to_sym), output_dir: output_dir, basename: basename)
        result = Result.new(coverage_blob, meta: meta, groups: groups)
        fmt.format(result, output_dir: output_dir, basename: basename)
      end

      # Load a merged or raw JSON file from disk and write all requested formats.
      def self.write_from_json_file(json_path, **kwargs)
        text = File.read(json_path)
        data = JSON.parse(text)
        blob = Merge.extract_coverage_blob(data)
        meta = kwargs.delete(:meta) || data["meta"] || {}
        groups =
          if kwargs.key?(:groups)
            kwargs.delete(:groups)
          else
            data["groups"]
          end
        write(blob, meta: meta, groups: groups, **kwargs)
      end
    end
  end
end
