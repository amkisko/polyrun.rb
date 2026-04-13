require "fileutils"
require "json"

require_relative "merge"
require_relative "result"

module Polyrun
  module Coverage
    # Formatters matching SimpleCov: +#format(result)+ receives a {Result} (and optional +output_dir+/+basename+).
    # Use {MultiFormatter} to run several outputs; {Formatter.multi} builds that from symbols.
    module Formatter
      module_function

      def multi(*names, output_dir:, basename: "polyrun-coverage")
        names = names.flatten.compact
        raise ArgumentError, "formatter.multi: need at least one format" if names.empty?

        formatters = names.map { |n| builtin(n).new(output_dir: output_dir, basename: basename) }
        MultiFormatter.new(formatters)
      end

      def builtin(name)
        case name.to_sym
        when :json then JsonFormatter
        when :lcov then LcovFormatter
        when :cobertura then CoberturaFormatter
        when :console then ConsoleFormatter
        when :html then HtmlFormatter
        else
          raise ArgumentError, "unknown coverage format: #{name.inspect} (expected :json, :lcov, :cobertura, :console, :html)"
        end
      end

      # Base: subclasses implement +#write_files(result, output_dir, basename)+ returning +{ key => path }+.
      class Base
        def initialize(output_dir: nil, basename: "polyrun-coverage")
          @default_output_dir = output_dir
          @default_basename = basename
        end

        def format(result, output_dir: @default_output_dir, basename: @default_basename)
          od = output_dir
          raise ArgumentError, "#{self.class}: output_dir is required" if od.nil? || od.to_s.empty?

          bn = basename || "polyrun-coverage"
          FileUtils.mkdir_p(od)
          write_files(result, od.to_s, bn.to_s)
        end

        def write_files(_result, _output_dir, _basename)
          raise NotImplementedError
        end
      end

      # Runs each formatter in order; merges returned path hashes (later keys win on duplicate).
      class MultiFormatter
        def initialize(formatters)
          @formatters = Array(formatters)
        end

        attr_reader :formatters

        def format(result, **kwargs)
          @formatters.each_with_object({}) do |f, acc|
            acc.merge!(f.format(result, **kwargs))
          end
        end
      end

      class JsonFormatter < Base
        def write_files(result, output_dir, basename)
          path = File.join(output_dir, "#{basename}.json")
          payload = Merge.to_simplecov_json(result.coverage_blob, meta: result.meta, groups: result.groups)
          File.write(path, JSON.generate(payload))
          {json: path}
        end
      end

      class LcovFormatter < Base
        def write_files(result, output_dir, basename)
          path = File.join(output_dir, "#{basename}.lcov")
          File.write(path, Merge.emit_lcov(result.coverage_blob))
          {lcov: path}
        end
      end

      class CoberturaFormatter < Base
        def write_files(result, output_dir, basename)
          path = File.join(output_dir, "#{basename}.xml")
          root = result.meta && (result.meta["polyrun_coverage_root"] || result.meta[:polyrun_coverage_root])
          File.write(path, Merge.emit_cobertura(result.coverage_blob, root: root))
          {cobertura: path}
        end
      end

      class ConsoleFormatter < Base
        def write_files(result, output_dir, basename)
          path = File.join(output_dir, "#{basename}-summary.txt")
          summary = Merge.console_summary(result.coverage_blob)
          File.write(path, Merge.format_console_summary(summary))
          {console: path}
        end
      end

      class HtmlFormatter < Base
        def write_files(result, output_dir, basename)
          path = File.join(output_dir, "#{basename}.html")
          title = (result.meta && result.meta["title"]) || (result.meta && result.meta[:title]) || "Polyrun coverage"
          File.write(path, Merge.emit_html(result.coverage_blob, title: title))
          {html: path}
        end
      end
    end
  end
end
